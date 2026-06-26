package mailapi_test

import (
	"bytes"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"mailanchor/serverd/internal/auth"
	"mailanchor/serverd/internal/config"
	"mailanchor/serverd/internal/db"
	"mailanchor/serverd/internal/mailapi"
	"mailanchor/serverd/internal/retry"
	"mailanchor/serverd/internal/server"
	"mailanchor/serverd/internal/storage"
)

// --- fakes ---

type fakeSender struct {
	mu   sync.Mutex
	sent []mailapi.OutgoingMail
	fail bool
}

func (f *fakeSender) Send(_ mailapi.ExternalAccount, m mailapi.OutgoingMail) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.fail {
		return io.ErrClosedPipe // transient
	}
	f.sent = append(f.sent, m)
	return nil
}

type fakeSource struct {
	batches []mailapi.ChangeBatch
	calls   int
	fail    bool
}

func (f *fakeSource) FetchChanges(_ mailapi.ExternalAccount, _ string, _ int) (mailapi.ChangeBatch, error) {
	if f.fail {
		return mailapi.ChangeBatch{}, io.ErrUnexpectedEOF
	}
	if f.calls >= len(f.batches) {
		return mailapi.ChangeBatch{HasMore: false}, nil
	}
	b := f.batches[f.calls]
	f.calls++
	return b, nil
}

type fakeOAuth struct {
	email string
	fail  bool
}

func (f *fakeOAuth) Exchange(_, _ string) (string, mailapi.Credential, error) {
	if f.fail {
		return "", mailapi.Credential{}, io.ErrClosedPipe
	}
	return f.email, mailapi.Credential{AccessToken: "at", RefreshToken: "rt", Expiry: time.Now().Add(time.Hour)}, nil
}

func (f *fakeOAuth) Refresh(_, _ string) (mailapi.Credential, error) {
	if f.fail {
		return mailapi.Credential{}, io.ErrClosedPipe
	}
	return mailapi.Credential{AccessToken: "at2", RefreshToken: "rt", Expiry: time.Now().Add(time.Hour)}, nil
}

// p2env extends the base test harness with the injected fakes.
type p2env struct {
	*env
	sender *fakeSender
	source *fakeSource
	oauth  *fakeOAuth
	blob   storage.Blob
}

// advancingClock returns a clock that advances 1s per call so updated_at timestamps
// are strictly monotonic (needed by the optimistic-concurrency draft test).
func advancingClock() func() time.Time {
	base := time.Date(2026, 6, 22, 9, 0, 0, 0, time.UTC)
	var mu sync.Mutex
	n := 0
	return func() time.Time {
		mu.Lock()
		defer mu.Unlock()
		t := base.Add(time.Duration(n) * time.Second)
		n++
		return t
	}
}

func setupP2(t *testing.T) *p2env { return setupP2With(t, nil) }

// setupP2With builds the phase-2 harness and lets a caller mutate Deps before the
// server is constructed (e.g. drop the Sender to reproduce the "sender not configured"
// 502 root cause from NR0003 / TR0005).
func setupP2With(t *testing.T, mutate func(*mailapi.Deps)) *p2env {
	t.Helper()
	conn, err := db.Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { conn.Close() })

	u, err := auth.NewStore(conn).CreateUser("u@example.com", "pw", "U")
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	st := mailapi.NewStore(conn)
	acct, err := st.InsertAccount(u.ID, "u@example.com", "imap", "", "2026-06-22T00:00:00Z")
	if err != nil {
		t.Fatalf("InsertAccount: %v", err)
	}

	blob, err := storage.NewDiskStore(filepath.Join(t.TempDir(), "blob"))
	if err != nil {
		t.Fatalf("blob: %v", err)
	}
	sender := &fakeSender{}
	source := &fakeSource{}
	oauth := &fakeOAuth{email: "second@example.com"}
	deps := mailapi.Deps{
		Sender:    sender,
		Source:    source,
		OAuth:     oauth,
		Secrets:   mailapi.NewMemSecretStore(),
		Blob:      blob,
		Now:       advancingClock(),
		SendRetry: retry.Policy{MaxAttempts: 2, Base: 0, Factor: 1, Max: 0, Jitter: 0}, // no real sleep
	}
	if mutate != nil {
		mutate(&deps)
	}
	cfg := config.Config{
		Context: "/api/v1", JWTSecret: []byte("test-secret"),
		AccessTTL: 900 * time.Second, RefreshTTL: 30 * 24 * time.Hour,
	}
	ts := httptest.NewServer(server.NewWithDeps(cfg, conn, deps))
	t.Cleanup(ts.Close)

	e := &env{ts: ts, user: u.ID, acct: acct.AccountID}
	var lr struct {
		Data struct {
			AccessToken string `json:"access_token"`
		} `json:"data"`
	}
	e.do(t, http.MethodPost, "/api/v1/auth/login", "",
		map[string]any{"email": "u@example.com", "password": "pw"}, http.StatusOK, &lr)
	e.token = lr.Data.AccessToken
	if e.token == "" {
		t.Fatal("no access token")
	}
	return &p2env{env: e, sender: sender, source: source, oauth: oauth, blob: blob}
}

// upload posts a multipart/form-data attachment and returns the raw response body.
func (e *env) upload(t *testing.T, token, draftID, filename string, content []byte, wantStatus int, out any) []byte {
	t.Helper()
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	if draftID != "" {
		_ = mw.WriteField("draft_id", draftID)
	}
	if filename != "" {
		fw, _ := mw.CreateFormFile("file", filename)
		_, _ = fw.Write(content)
	}
	mw.Close()
	req, _ := http.NewRequest(http.MethodPost, e.ts.URL+"/api/v1/attachments", &body)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("upload: %v", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != wantStatus {
		t.Fatalf("upload status=%d want=%d body=%s", resp.StatusCode, wantStatus, raw)
	}
	if out != nil && len(raw) > 0 {
		if err := json.Unmarshal(raw, out); err != nil {
			t.Fatalf("unmarshal upload: %v (%s)", err, raw)
		}
	}
	return raw
}

// --- send (D) ---

func TestSendMail(t *testing.T) {
	e := setupP2(t)
	tok := e.token

	// valid send -> 201 sent
	var sres struct {
		Data struct {
			MailID   string `json:"mail_id"`
			ThreadID string `json:"thread_id"`
			Status   string `json:"status"`
			SentAt   string `json:"sent_at"`
		} `json:"data"`
	}
	e.do(t, http.MethodPost, "/api/v1/mails", tok, map[string]any{
		"to":      []map[string]any{{"address": "boss@example.com"}},
		"subject": "Weekly report",
		"body":    map[string]any{"format": "text", "content": "Here is the report."},
	}, http.StatusCreated, &sres)
	if sres.Data.Status != "sent" || sres.Data.MailID == "" {
		t.Fatalf("send result: %+v", sres.Data)
	}
	if len(e.sender.sent) != 1 {
		t.Fatalf("sender not invoked: %d", len(e.sender.sent))
	}

	// the outbound mail is persisted and listable
	var lst struct {
		Data []mailapi.MailSummary `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/mails", tok, nil, http.StatusOK, &lst)
	if len(lst.Data) != 1 || lst.Data[0].Subject != "Weekly report" {
		t.Fatalf("outbound not persisted/listable: %+v", lst.Data)
	}

	// recipient invalid -> 422
	raw := e.do(t, http.MethodPost, "/api/v1/mails", tok, map[string]any{
		"to":      []map[string]any{{"address": "broken-address"}},
		"subject": "x", "body": map[string]any{"format": "text", "content": "y"},
	}, http.StatusUnprocessableEntity, nil)
	if errCode(raw) != "RECIPIENT_INVALID" {
		t.Fatalf("want RECIPIENT_INVALID, got %s", raw)
	}

	// zero recipients -> 422 RECIPIENT_INVALID (L0012 §2.4; NR0011 B5)
	raw = e.do(t, http.MethodPost, "/api/v1/mails", tok, map[string]any{
		"to": []map[string]any{}, "subject": "x", "body": map[string]any{"format": "text", "content": "y"},
	}, http.StatusUnprocessableEntity, nil)
	if errCode(raw) != "RECIPIENT_INVALID" {
		t.Fatalf("want RECIPIENT_INVALID, got %s", raw)
	}

	// external send failure -> 502 SEND_FAILED, nothing persisted
	e.sender.fail = true
	raw = e.do(t, http.MethodPost, "/api/v1/mails", tok, map[string]any{
		"to":      []map[string]any{{"address": "boss@example.com"}},
		"subject": "failed", "body": map[string]any{"format": "text", "content": "z"},
	}, http.StatusBadGateway, nil)
	if errCode(raw) != "SEND_FAILED" {
		t.Fatalf("want SEND_FAILED, got %s", raw)
	}
	e.do(t, http.MethodGet, "/api/v1/mails", tok, nil, http.StatusOK, &lst)
	if len(lst.Data) != 1 {
		t.Fatalf("failed send must not persist: %d mails", len(lst.Data))
	}
}

// B0001 / 502 root cause (NR0003 §1, TR0005): when no SMTP relay is configured
// (MAILANCHOR_SMTP_HOST empty -> router leaves Deps.Sender nil), POST /api/v1/mails must
// return 502 SEND_FAILED with details.reason "sender not configured" and persist nothing.
// This is the live failure operators hit with only Google OAuth keys set; it was asserted
// only for the transient send-failure path before, never for the nil-Sender path itself.
func TestSendMailSenderNotConfigured(t *testing.T) {
	e := setupP2With(t, func(d *mailapi.Deps) { d.Sender = nil })
	tok := e.token

	raw := e.do(t, http.MethodPost, "/api/v1/mails", tok, map[string]any{
		"to":      []map[string]any{{"address": "boss@example.com"}},
		"subject": "no relay",
		"body":    map[string]any{"format": "text", "content": "should not send"},
	}, http.StatusBadGateway, nil)

	if errCode(raw) != "SEND_FAILED" {
		t.Fatalf("want SEND_FAILED, got %s", raw)
	}
	var er struct {
		Error struct {
			Details struct {
				Reason string `json:"reason"`
			} `json:"details"`
		} `json:"error"`
	}
	if err := json.Unmarshal(raw, &er); err != nil {
		t.Fatalf("unmarshal error body: %v (%s)", err, raw)
	}
	if er.Error.Details.Reason != "sender not configured" {
		t.Fatalf("want reason 'sender not configured', got %q (%s)", er.Error.Details.Reason, raw)
	}

	// nothing persisted: a failed send must not leave an outbound mail
	var lst struct {
		Data []mailapi.MailSummary `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/mails", tok, nil, http.StatusOK, &lst)
	if len(lst.Data) != 0 {
		t.Fatalf("sender-not-configured send must not persist: %d mails", len(lst.Data))
	}
}

// NR0011 B1: an unknown/foreign attachment_id must be rejected BEFORE the external send,
// so the mail is never relayed while the API reports 404. Previously ownership was checked
// only in persistSent (after Sender.Send), causing a sent-but-404 split-brain.
func TestSendForeignAttachmentRejectedBeforeSend(t *testing.T) {
	e := setupP2(t)
	tok := e.token

	raw := e.do(t, http.MethodPost, "/api/v1/mails", tok, map[string]any{
		"to":             []map[string]any{{"address": "boss@example.com"}},
		"subject":        "x",
		"body":           map[string]any{"format": "text", "content": "y"},
		"attachment_ids": []string{"a_not_mine"},
	}, http.StatusNotFound, nil)
	if errCode(raw) != "ATTACHMENT_NOT_FOUND" {
		t.Fatalf("want ATTACHMENT_NOT_FOUND, got %s", raw)
	}
	// the key invariant: the external sender was NOT invoked
	if len(e.sender.sent) != 0 {
		t.Fatalf("mail must not be sent when an attachment id is invalid: %d sends", len(e.sender.sent))
	}
}

func TestSendFromDraftReattachesAttachment(t *testing.T) {
	e := setupP2(t)
	tok := e.token

	// create a draft
	var dr struct {
		Data struct {
			DraftID   string `json:"draft_id"`
			UpdatedAt string `json:"updated_at"`
		} `json:"data"`
	}
	e.do(t, http.MethodPost, "/api/v1/drafts", tok, map[string]any{
		"to": []map[string]any{{"address": "boss@example.com"}}, "subject": "Draft",
		"body": map[string]any{"format": "text", "content": "Body"},
	}, http.StatusCreated, &dr)
	draftID := dr.Data.DraftID

	// upload an attachment bound to the draft
	var ar struct {
		Data mailapi.Attachment `json:"data"`
	}
	e.upload(t, tok, draftID, "report.pdf", []byte("PDFDATA"), http.StatusCreated, &ar)
	if ar.Data.AttachmentID == "" || ar.Data.SizeBytes != int64(len("PDFDATA")) {
		t.Fatalf("upload result: %+v", ar.Data)
	}

	// send from the draft
	var sres struct {
		Data struct {
			MailID string `json:"mail_id"`
		} `json:"data"`
	}
	e.do(t, http.MethodPost, "/api/v1/mails", tok, map[string]any{
		"from_draft_id": draftID,
		"to":            []map[string]any{{"address": "boss@example.com"}},
		"subject":       "Draft", "body": map[string]any{"format": "text", "content": "Body"},
	}, http.StatusCreated, &sres)

	// the mail now carries the attachment (reattached) and has_attachment is true
	var dt struct {
		Data mailapi.MailDetail `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/mails/"+sres.Data.MailID, tok, nil, http.StatusOK, &dt)
	if len(dt.Data.Attachments) != 1 {
		t.Fatalf("attachment not reattached: %+v", dt.Data.Attachments)
	}
	// the source draft is gone
	e.do(t, http.MethodGet, "/api/v1/drafts/"+draftID, tok, nil, http.StatusNotFound, nil)

	// the reattached attachment is downloadable with original bytes
	aid := dt.Data.Attachments[0].AttachmentID
	req, _ := http.NewRequest(http.MethodGet, e.ts.URL+"/api/v1/attachments/"+aid, nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("download: %v", err)
	}
	defer resp.Body.Close()
	got, _ := io.ReadAll(resp.Body)
	if string(got) != "PDFDATA" {
		t.Fatalf("downloaded bytes mismatch: %q", got)
	}
	if cd := resp.Header.Get("Content-Disposition"); cd == "" {
		t.Fatalf("missing Content-Disposition")
	}
}

// NR0011 G1: an invalid draft enum (reply_type) must be a 422 VALIDATION_FAILED, not a
// 500 leaking from the SQLite CHECK constraint.
func TestDraftInvalidEnumIs422(t *testing.T) {
	e := setupP2(t)
	tok := e.token

	raw := e.do(t, http.MethodPost, "/api/v1/drafts", tok, map[string]any{
		"reply_type": "bogus", "subject": "x",
		"body": map[string]any{"format": "text", "content": "y"},
	}, http.StatusBadRequest, nil)
	if errCode(raw) != "VALIDATION_FAILED" {
		t.Fatalf("want VALIDATION_FAILED for bad reply_type, got %s", raw)
	}

	raw = e.do(t, http.MethodPost, "/api/v1/drafts", tok, map[string]any{
		"body": map[string]any{"format": "rtf", "content": "y"},
	}, http.StatusBadRequest, nil)
	if errCode(raw) != "VALIDATION_FAILED" {
		t.Fatalf("want VALIDATION_FAILED for bad body.format, got %s", raw)
	}

	// a valid reply_type still works
	e.do(t, http.MethodPost, "/api/v1/drafts", tok, map[string]any{
		"reply_type": "reply", "subject": "ok",
		"body": map[string]any{"format": "html", "content": "<p>y</p>"},
	}, http.StatusCreated, nil)
}

// --- drafts (D) optimistic concurrency ---

func TestDraftOptimisticConcurrency(t *testing.T) {
	e := setupP2(t)
	tok := e.token

	var dr struct {
		Data struct {
			DraftID   string `json:"draft_id"`
			UpdatedAt string `json:"updated_at"`
		} `json:"data"`
	}
	e.do(t, http.MethodPost, "/api/v1/drafts", tok, map[string]any{
		"subject": "v1", "body": map[string]any{"format": "text", "content": "a"},
	}, http.StatusCreated, &dr)
	id, base := dr.Data.DraftID, dr.Data.UpdatedAt

	// correct base -> 200 with a new updated_at
	var ur struct {
		Data struct {
			UpdatedAt string `json:"updated_at"`
		} `json:"data"`
	}
	e.do(t, http.MethodPut, "/api/v1/drafts/"+id, tok, map[string]any{
		"subject": "v2", "body": map[string]any{"format": "text", "content": "b"}, "base_updated_at": base,
	}, http.StatusOK, &ur)
	if ur.Data.UpdatedAt == "" || ur.Data.UpdatedAt == base {
		t.Fatalf("updated_at should advance: base=%s new=%s", base, ur.Data.UpdatedAt)
	}

	// stale base -> 409 DRAFT_CONFLICT
	raw := e.do(t, http.MethodPut, "/api/v1/drafts/"+id, tok, map[string]any{
		"subject": "v3", "body": map[string]any{"format": "text", "content": "c"}, "base_updated_at": base,
	}, http.StatusConflict, nil)
	if errCode(raw) != "DRAFT_CONFLICT" {
		t.Fatalf("want DRAFT_CONFLICT, got %s", raw)
	}

	// delete -> 204, then update -> 404
	e.do(t, http.MethodDelete, "/api/v1/drafts/"+id, tok, nil, http.StatusNoContent, nil)
	raw = e.do(t, http.MethodPut, "/api/v1/drafts/"+id, tok, map[string]any{
		"subject": "v4", "body": map[string]any{"format": "text", "content": "d"}, "base_updated_at": ur.Data.UpdatedAt,
	}, http.StatusNotFound, nil)
	if errCode(raw) != "MAIL_NOT_FOUND" {
		t.Fatalf("want MAIL_NOT_FOUND, got %s", raw)
	}
}

// --- attachments (D) ---

func TestAttachmentUploadValidation(t *testing.T) {
	e := setupP2(t)
	tok := e.token

	// missing draft_id -> 400
	raw := e.upload(t, tok, "", "f.txt", []byte("x"), http.StatusBadRequest, nil)
	if errCode(raw) != "VALIDATION_FAILED" {
		t.Fatalf("want VALIDATION_FAILED, got %s", raw)
	}

	// unknown draft -> 400 (draft not found)
	raw = e.upload(t, tok, "d_missing", "f.txt", []byte("x"), http.StatusBadRequest, nil)
	if errCode(raw) != "VALIDATION_FAILED" {
		t.Fatalf("want VALIDATION_FAILED, got %s", raw)
	}

	// download missing -> 404
	req, _ := http.NewRequest(http.MethodGet, e.ts.URL+"/api/v1/attachments/a_missing", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("download missing: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("download missing: status=%d", resp.StatusCode)
	}
}

// NR0011 S4: an over-limit attachment must be rejected with 413 PAYLOAD_TOO_LARGE, not
// silently truncated to the limit and stored as a corrupt partial.
func TestAttachmentUploadTooLarge(t *testing.T) {
	if testing.Short() {
		t.Skip("allocates >25MiB")
	}
	e := setupP2(t)
	tok := e.token

	// create a draft to bind the attachment to
	var dr struct {
		Data struct {
			DraftID string `json:"draft_id"`
		} `json:"data"`
	}
	e.do(t, http.MethodPost, "/api/v1/drafts", tok, map[string]any{
		"subject": "big", "body": map[string]any{"format": "text", "content": "x"},
	}, http.StatusCreated, &dr)

	oversize := bytes.Repeat([]byte("A"), (25<<20)+1) // uploadMaxBytes + 1
	raw := e.upload(t, tok, dr.Data.DraftID, "big.bin", oversize, http.StatusRequestEntityTooLarge, nil)
	if errCode(raw) != "PAYLOAD_TOO_LARGE" {
		t.Fatalf("want PAYLOAD_TOO_LARGE, got %s", raw)
	}
}

// --- accounts (M / OAuth) ---

func TestAccounts(t *testing.T) {
	e := setupP2(t)
	tok := e.token

	// list -> seeded imap account present
	var ls struct {
		Data []mailapi.Account `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/accounts", tok, nil, http.StatusOK, &ls)
	if len(ls.Data) != 1 {
		t.Fatalf("want 1 seeded account, got %+v", ls.Data)
	}

	// connect via OAuth -> 201
	var cr struct {
		Data mailapi.Account `json:"data"`
	}
	e.do(t, http.MethodPost, "/api/v1/accounts", tok, map[string]any{
		"provider": "gmail", "auth_code": "code_xyz",
	}, http.StatusCreated, &cr)
	if cr.Data.Email != "second@example.com" || cr.Data.Status != "connected" {
		t.Fatalf("account: %+v", cr.Data)
	}

	// duplicate email -> 409 ACCOUNT_DUPLICATE
	e.oauth.email = "second@example.com"
	raw := e.do(t, http.MethodPost, "/api/v1/accounts", tok, map[string]any{
		"provider": "gmail", "auth_code": "code_again",
	}, http.StatusConflict, nil)
	if errCode(raw) != "ACCOUNT_DUPLICATE" {
		t.Fatalf("want ACCOUNT_DUPLICATE, got %s", raw)
	}

	// bad provider -> 400
	raw = e.do(t, http.MethodPost, "/api/v1/accounts", tok, map[string]any{
		"provider": "icloud", "auth_code": "c",
	}, http.StatusBadRequest, nil)
	if errCode(raw) != "VALIDATION_FAILED" {
		t.Fatalf("want VALIDATION_FAILED, got %s", raw)
	}

	// delete the connected gmail account -> 204
	e.do(t, http.MethodDelete, "/api/v1/accounts/"+cr.Data.AccountID, tok, nil, http.StatusNoContent, nil)
	e.do(t, http.MethodGet, "/api/v1/accounts", tok, nil, http.StatusOK, &ls)
	if len(ls.Data) != 1 {
		t.Fatalf("after delete want 1 account, got %+v", ls.Data)
	}
}

// --- sync (F) merge engine ---

func TestSyncMerge(t *testing.T) {
	e := setupP2(t)
	tok := e.token

	// status -> idle initially
	var ss struct {
		Data mailapi.SyncStatusDTO `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/sync/status", tok, nil, http.StatusOK, &ss)
	if ss.Data.State != "idle" || ss.Data.Pending {
		t.Fatalf("initial status: %+v", ss.Data)
	}

	// first sync: two new inbound mails (one carries a user label + attachment)
	e.source.batches = []mailapi.ChangeBatch{{
		Items: []mailapi.ExternalChange{
			{Kind: mailapi.ChangeUpsert, ExternalID: "ext-1", ThreadKey: "th-1",
				From: mailapi.Address{Address: "a@x.com"}, Subject: "one",
				Body:       mailapi.Body{Format: "text", Content: "body one"},
				ReceivedAt: "2026-06-21T08:00:00Z", IsRead: false,
				Labels:      []string{"inbox", "Promotions"},
				Attachments: []mailapi.ExternalAttachment{{Filename: "a.pdf", ContentType: "application/pdf", SizeBytes: 10}}},
			{Kind: mailapi.ChangeUpsert, ExternalID: "ext-2", ThreadKey: "th-2",
				From: mailapi.Address{Address: "b@x.com"}, Subject: "two",
				Body:       mailapi.Body{Format: "text", Content: "body two"},
				ReceivedAt: "2026-06-21T09:00:00Z", IsRead: false, Labels: []string{"inbox"}},
		},
		NextCursor: "cur-1", HasMore: false,
	}}
	var tr struct {
		Data struct {
			State   string `json:"state"`
			Applied int    `json:"applied"`
		} `json:"data"`
	}
	e.do(t, http.MethodPost, "/api/v1/sync", tok, map[string]any{}, http.StatusAccepted, &tr)
	if tr.Data.Applied != 2 || tr.Data.State != "idle" {
		t.Fatalf("first sync: %+v", tr.Data)
	}

	// both mails appear in the read-path; the labeled one has an attachment
	var lst struct {
		Data []mailapi.MailSummary `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/mails", tok, nil, http.StatusOK, &lst)
	if len(lst.Data) != 2 {
		t.Fatalf("want 2 synced mails, got %d", len(lst.Data))
	}
	var one mailapi.MailSummary
	for _, m := range lst.Data {
		if m.Subject == "one" {
			one = m
		}
	}
	if one.MailID == "" || !one.HasAttachment {
		t.Fatalf("mail 'one' missing/attachment: %+v", one)
	}

	// status reflects completion with a last_synced_at
	e.do(t, http.MethodGet, "/api/v1/sync/status", tok, nil, http.StatusOK, &ss)
	if ss.Data.State != "idle" || ss.Data.LastSyncedAt == nil {
		t.Fatalf("post-sync status: %+v", ss.Data)
	}

	// mark mail 'one' as read locally
	e.do(t, http.MethodPatch, "/api/v1/mails/"+one.MailID, tok, map[string]any{"is_read": true}, http.StatusOK, nil)

	// second sync: ext-1 re-sent as unread (monotonic OR keeps it read), and a
	// duplicate insert of ext-1 must NOT create a second row (external_ref dedup);
	// ext-2 is deleted upstream.
	e.source.calls = 0
	e.source.batches = []mailapi.ChangeBatch{{
		Items: []mailapi.ExternalChange{
			{Kind: mailapi.ChangeUpsert, ExternalID: "ext-1", ThreadKey: "th-1",
				From: mailapi.Address{Address: "a@x.com"}, Subject: "one-updated",
				Body:       mailapi.Body{Format: "text", Content: "body one v2"},
				ReceivedAt: "2026-06-21T08:00:00Z", IsRead: false, Labels: []string{"inbox"}},
			{Kind: mailapi.ChangeDeleted, ExternalID: "ext-2"},
		},
		NextCursor: "cur-2", HasMore: false,
	}}
	e.do(t, http.MethodPost, "/api/v1/sync", tok, map[string]any{}, http.StatusAccepted, &tr)

	e.do(t, http.MethodGet, "/api/v1/mails", tok, nil, http.StatusOK, &lst)
	if len(lst.Data) != 1 {
		t.Fatalf("dedup+delete: want 1 mail, got %d (%+v)", len(lst.Data), lst.Data)
	}
	got := lst.Data[0]
	if got.Subject != "one-updated" {
		t.Fatalf("external authority on subject: %+v", got)
	}
	if !got.IsRead {
		t.Fatalf("monotonic is_read OR violated: read mail regressed to unread")
	}

	// the labeled-mail detail no longer has the attachment (ext-1 v2 carried none)
	var dt struct {
		Data mailapi.MailDetail `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/mails/"+got.MailID, tok, nil, http.StatusOK, &dt)
	if len(dt.Data.Attachments) != 0 {
		t.Fatalf("attachment authority: expected cleared, got %+v", dt.Data.Attachments)
	}
}

// --- sync upstream failure ---

func TestSyncSourceFailure(t *testing.T) {
	e := setupP2(t)
	tok := e.token
	e.source.fail = true
	e.do(t, http.MethodPost, "/api/v1/sync", tok, map[string]any{}, http.StatusAccepted, nil)
	// account sync_state should be in error after a failed fetch
	var ss struct {
		Data mailapi.SyncStatusDTO `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/sync/status", tok, nil, http.StatusOK, &ss)
	if ss.Data.State != "error" {
		t.Fatalf("want error state after fetch failure, got %+v", ss.Data)
	}
}
