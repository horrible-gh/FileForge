package mailapi_test

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"mailanchor/serverd/internal/auth"
	"mailanchor/serverd/internal/config"
	"mailanchor/serverd/internal/db"
	"mailanchor/serverd/internal/mailapi"
	"mailanchor/serverd/internal/server"
)

type env struct {
	ts    *httptest.Server
	token string
	user  string
	acct  string
}

func setup(t *testing.T) *env {
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
	// a mail_account row is needed for the mail FK; insert directly.
	acct := "acc_test"
	if _, err := conn.Exec(
		`INSERT INTO mail_account(account_id,user_id,email,provider,status,connected_at)
		 VALUES(?,?,?, 'imap', 'connected', ?)`,
		acct, u.ID, "u@example.com", "2026-06-21T00:00:00Z"); err != nil {
		t.Fatalf("seed account: %v", err)
	}
	st := mailapi.NewStore(conn)
	for i, subj := range []string{"first", "second", "third"} {
		ts := []string{"2026-06-21T08:00:0" + string(rune('0'+i)) + "Z"}[0]
		if _, err := st.SeedMail(u.ID, acct, mailapi.MailSummary{
			ThreadID: "t_x", From: mailapi.Address{Name: "발신자", Address: "sender@shop.com"},
			Subject: subj, Snippet: subj + " body", ReceivedAt: ts,
		}, "<p>"+subj+"</p>", []mailapi.Address{{Address: "u@example.com"}}); err != nil {
			t.Fatalf("seed mail: %v", err)
		}
	}

	cfg := config.Config{
		Context:    "/api/v1",
		JWTSecret:  []byte("test-secret"),
		AccessTTL:  900 * time.Second,
		RefreshTTL: 30 * 24 * time.Hour,
	}
	ts := httptest.NewServer(server.New(cfg, conn))
	t.Cleanup(ts.Close)

	e := &env{ts: ts, user: u.ID, acct: acct}
	// login -> access token
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
	return e
}

func (e *env) do(t *testing.T, method, path, token string, body any, wantStatus int, out any) []byte {
	t.Helper()
	var rdr io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rdr = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, e.ts.URL+path, rdr)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != wantStatus {
		t.Fatalf("%s %s: status=%d want=%d body=%s", method, path, resp.StatusCode, wantStatus, raw)
	}
	if out != nil && len(raw) > 0 {
		if err := json.Unmarshal(raw, out); err != nil {
			t.Fatalf("unmarshal %s: %v (%s)", path, err, raw)
		}
	}
	return raw
}

func errCode(raw []byte) string {
	var e struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	_ = json.Unmarshal(raw, &e)
	return e.Error.Code
}

func TestLabels(t *testing.T) {
	e := setup(t)
	tok := e.token

	// system labels seeded
	var ll struct {
		Data []mailapi.Label `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/labels", tok, nil, http.StatusOK, &ll)
	sys := map[string]bool{}
	for _, l := range ll.Data {
		if l.Type == "system" {
			sys[l.Name] = true
		}
	}
	for _, name := range []string{"inbox", "sent", "draft"} {
		if !sys[name] {
			t.Fatalf("missing system label %q", name)
		}
	}

	// create user label
	var cr struct {
		Data mailapi.Label `json:"data"`
	}
	e.do(t, http.MethodPost, "/api/v1/labels", tok, map[string]any{"name": "영수증", "color": "#3B82F6"}, http.StatusCreated, &cr)
	if cr.Data.LabelID == "" || cr.Data.Type != "user" {
		t.Fatalf("bad created label: %+v", cr.Data)
	}
	userLabel := cr.Data.LabelID

	// duplicate -> 409
	raw := e.do(t, http.MethodPost, "/api/v1/labels", tok, map[string]any{"name": "영수증"}, http.StatusConflict, nil)
	if errCode(raw) != "LABEL_DUPLICATE" {
		t.Fatalf("want LABEL_DUPLICATE, got %s", raw)
	}

	// system label is immutable -> 403
	raw = e.do(t, http.MethodPatch, "/api/v1/labels/inbox_"+e.user, tok, map[string]any{"name": "x"}, http.StatusForbidden, nil)
	if errCode(raw) != "FORBIDDEN" {
		t.Fatalf("want FORBIDDEN, got %s", raw)
	}

	// delete user label -> 204
	e.do(t, http.MethodDelete, "/api/v1/labels/"+userLabel, tok, nil, http.StatusNoContent, nil)
	// delete missing -> 404
	raw = e.do(t, http.MethodDelete, "/api/v1/labels/lbl_missing", tok, nil, http.StatusNotFound, nil)
	if errCode(raw) != "LABEL_NOT_FOUND" {
		t.Fatalf("want LABEL_NOT_FOUND, got %s", raw)
	}
}

func TestMailReadPath(t *testing.T) {
	e := setup(t)
	tok := e.token

	// list with limit=2 -> has_more true, cursor present
	var l1 struct {
		Data []mailapi.MailSummary `json:"data"`
		Meta mailapi.PageMeta      `json:"meta"`
	}
	e.do(t, http.MethodGet, "/api/v1/mails?limit=2", tok, nil, http.StatusOK, &l1)
	if len(l1.Data) != 2 || !l1.Meta.HasMore || l1.Meta.NextCursor == nil {
		t.Fatalf("page1 unexpected: %+v meta=%+v", l1.Data, l1.Meta)
	}
	// newest first (third has highest received_at)
	if l1.Data[0].Subject != "third" {
		t.Fatalf("want newest-first, got %s", l1.Data[0].Subject)
	}

	// next page via cursor -> remaining 1, has_more false
	var l2 struct {
		Data []mailapi.MailSummary `json:"data"`
		Meta mailapi.PageMeta      `json:"meta"`
	}
	e.do(t, http.MethodGet, "/api/v1/mails?limit=2&cursor="+*l1.Meta.NextCursor, tok, nil, http.StatusOK, &l2)
	if len(l2.Data) != 1 || l2.Meta.HasMore || l2.Meta.NextCursor != nil {
		t.Fatalf("page2 unexpected: %+v meta=%+v", l2.Data, l2.Meta)
	}

	mailID := l1.Data[0].MailID

	// detail
	var dt struct {
		Data mailapi.MailDetail `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/mails/"+mailID, tok, nil, http.StatusOK, &dt)
	if dt.Data.Body.Content == "" || dt.Data.From.Address == "" {
		t.Fatalf("detail missing fields: %+v", dt.Data)
	}

	// missing mail -> 404
	raw := e.do(t, http.MethodGet, "/api/v1/mails/m_missing", tok, nil, http.StatusNotFound, nil)
	if errCode(raw) != "MAIL_NOT_FOUND" {
		t.Fatalf("want MAIL_NOT_FOUND, got %s", raw)
	}

	// patch: mark read + add a label
	var cr struct {
		Data mailapi.Label `json:"data"`
	}
	e.do(t, http.MethodPost, "/api/v1/labels", tok, map[string]any{"name": "work"}, http.StatusCreated, &cr)
	var pr struct {
		Data struct {
			IsRead bool     `json:"is_read"`
			Labels []string `json:"labels"`
		} `json:"data"`
	}
	e.do(t, http.MethodPatch, "/api/v1/mails/"+mailID, tok,
		map[string]any{"is_read": true, "labels_add": []string{cr.Data.LabelID}}, http.StatusOK, &pr)
	if !pr.Data.IsRead || len(pr.Data.Labels) != 1 || pr.Data.Labels[0] != cr.Data.LabelID {
		t.Fatalf("patch result unexpected: %+v", pr.Data)
	}

	// patch with unknown label -> 404 LABEL_NOT_FOUND
	raw = e.do(t, http.MethodPatch, "/api/v1/mails/"+mailID, tok,
		map[string]any{"labels_add": []string{"lbl_nope"}}, http.StatusNotFound, nil)
	if errCode(raw) != "LABEL_NOT_FOUND" {
		t.Fatalf("want LABEL_NOT_FOUND, got %s", raw)
	}

	// unread filter should now exclude the read mail
	var lu struct {
		Data []mailapi.MailSummary `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/mails?unread=true", tok, nil, http.StatusOK, &lu)
	for _, m := range lu.Data {
		if m.MailID == mailID {
			t.Fatalf("read mail should be excluded from unread filter")
		}
	}
}

func TestSettingsAndAuthGuard(t *testing.T) {
	e := setup(t)
	tok := e.token

	// default display
	var d struct {
		Data mailapi.Display `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/settings/display", tok, nil, http.StatusOK, &d)
	if d.Data.Language != "ko" || d.Data.SortOrder != "date_desc" {
		t.Fatalf("unexpected defaults: %+v", d.Data)
	}

	// valid patch
	e.do(t, http.MethodPatch, "/api/v1/settings/display", tok, map[string]any{"language": "ja"}, http.StatusOK, nil)
	// invalid enum -> 400
	raw := e.do(t, http.MethodPatch, "/api/v1/settings/display", tok, map[string]any{"language": "xx"}, http.StatusBadRequest, nil)
	if errCode(raw) != "VALIDATION_FAILED" {
		t.Fatalf("want VALIDATION_FAILED, got %s", raw)
	}

	// no token -> TOKEN_INVALID
	raw = e.do(t, http.MethodGet, "/api/v1/labels", "", nil, http.StatusUnauthorized, nil)
	if errCode(raw) != "TOKEN_INVALID" {
		t.Fatalf("want TOKEN_INVALID, got %s", raw)
	}
}
