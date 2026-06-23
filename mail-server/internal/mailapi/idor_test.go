package mailapi_test

import (
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
	"mailanchor/serverd/internal/storage"
)

// NR0011 T4: cross-user (IDOR) regression. All resource queries are manually user-scoped;
// this proves user B cannot read/mutate user A's mail/draft/attachment by guessing the id
// (the scoping miss would leak data, so it warrants explicit coverage).
func TestCrossUserIsolation(t *testing.T) {
	conn, err := db.Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { conn.Close() })

	as := auth.NewStore(conn)
	uA, err := as.CreateUser("a@example.com", "pw", "A")
	if err != nil {
		t.Fatalf("CreateUser A: %v", err)
	}
	if _, err := as.CreateUser("b@example.com", "pw", "B"); err != nil {
		t.Fatalf("CreateUser B: %v", err)
	}

	st := mailapi.NewStore(conn)
	acctA, err := st.InsertAccount(uA.ID, "a@example.com", "imap", "", "2026-06-22T00:00:00Z")
	if err != nil {
		t.Fatalf("InsertAccount: %v", err)
	}
	mailID, err := st.SeedMail(uA.ID, acctA.AccountID, mailapi.MailSummary{
		ThreadID: "t1", From: mailapi.Address{Address: "x@y.com"}, Subject: "secret",
		Snippet: "s", ReceivedAt: "2026-06-21T08:00:00Z",
	}, "<p>secret</p>", []mailapi.Address{{Address: "a@example.com"}})
	if err != nil {
		t.Fatalf("SeedMail: %v", err)
	}

	blob, err := storage.NewDiskStore(filepath.Join(t.TempDir(), "blob"))
	if err != nil {
		t.Fatalf("blob: %v", err)
	}
	cfg := config.Config{Context: "/api/v1", JWTSecret: []byte("test-secret"),
		AccessTTL: 900 * time.Second, RefreshTTL: 30 * 24 * time.Hour}
	ts := httptest.NewServer(server.NewWithDeps(cfg, conn,
		mailapi.Deps{Blob: blob, Secrets: mailapi.NewMemSecretStore()}))
	t.Cleanup(ts.Close)
	e := &env{ts: ts}

	login := func(email string) string {
		var lr struct {
			Data struct {
				AccessToken string `json:"access_token"`
			} `json:"data"`
		}
		e.do(t, http.MethodPost, "/api/v1/auth/login", "",
			map[string]any{"email": email, "password": "pw"}, http.StatusOK, &lr)
		return lr.Data.AccessToken
	}
	tokenA := login("a@example.com")
	tokenB := login("b@example.com")

	// A creates a draft and uploads an attachment to it
	var dr struct {
		Data struct {
			DraftID string `json:"draft_id"`
		} `json:"data"`
	}
	e.do(t, http.MethodPost, "/api/v1/drafts", tokenA, map[string]any{
		"subject": "draftA", "body": map[string]any{"format": "text", "content": "c"},
	}, http.StatusCreated, &dr)
	draftID := dr.Data.DraftID
	var ar struct {
		Data mailapi.Attachment `json:"data"`
	}
	e.upload(t, tokenA, draftID, "a.txt", []byte("bytes"), http.StatusCreated, &ar)
	attID := ar.Data.AttachmentID

	// B must not reach any of A's resources by id
	raw := e.do(t, http.MethodGet, "/api/v1/mails/"+mailID, tokenB, nil, http.StatusNotFound, nil)
	if errCode(raw) != "MAIL_NOT_FOUND" {
		t.Fatalf("mail read leak: %s", raw)
	}
	e.do(t, http.MethodPatch, "/api/v1/mails/"+mailID, tokenB, map[string]any{"is_read": true}, http.StatusNotFound, nil)
	raw = e.do(t, http.MethodGet, "/api/v1/drafts/"+draftID, tokenB, nil, http.StatusNotFound, nil)
	if errCode(raw) != "MAIL_NOT_FOUND" {
		t.Fatalf("draft read leak: %s", raw)
	}
	e.do(t, http.MethodPut, "/api/v1/drafts/"+draftID, tokenB, map[string]any{
		"subject": "hijack", "body": map[string]any{"format": "text", "content": "z"},
		"base_updated_at": "2026-06-22T00:00:00Z",
	}, http.StatusNotFound, nil)

	// attachment download by B -> 404 (download is raw bytes, not a JSON envelope)
	req, _ := http.NewRequest(http.MethodGet, ts.URL+"/api/v1/attachments/"+attID, nil)
	req.Header.Set("Authorization", "Bearer "+tokenB)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("download: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("attachment IDOR leak: status=%d", resp.StatusCode)
	}

	// sanity: A still reaches its own mail
	e.do(t, http.MethodGet, "/api/v1/mails/"+mailID, tokenA, nil, http.StatusOK, nil)
}
