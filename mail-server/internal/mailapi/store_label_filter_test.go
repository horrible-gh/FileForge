package mailapi

import (
	"path/filepath"
	"testing"

	"mailanchor/serverd/internal/auth"
	"mailanchor/serverd/internal/db"
)

// seedLabeledMail opens a fresh DB, creates a user (which seeds the inbox/sent/draft
// system labels) + a connected account, then inserts one mail and attaches it to the
// given system label NAME via the per-user label_id (exactly how the sync write-path
// stores it). Returns the store and the user id.
func seedLabeledMail(t *testing.T, mailID, labelName string) (*Store, string) {
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
	if _, err := conn.Exec(
		`INSERT INTO mail_account(account_id,user_id,email,provider,status,connected_at)
		 VALUES('acc1',?,?, 'imap', 'connected', '2026-06-22T00:00:00Z')`,
		u.ID, "u@example.com"); err != nil {
		t.Fatalf("seed account: %v", err)
	}
	if _, err := conn.Exec(
		`INSERT INTO mail(mail_id,user_id,account_id,thread_id,from_addr,subject,received_at,direction)
		 VALUES(?,?, 'acc1','th','{"address":"a@b.c"}','hi','2026-06-26T00:00:00Z','inbound')`,
		mailID, u.ID); err != nil {
		t.Fatalf("seed mail: %v", err)
	}
	// Store the label the way the sync write-path does: by per-user label_id, not name.
	if _, err := conn.Exec(
		`INSERT INTO mail_label(mail_id,label_id) VALUES(?,?)`,
		mailID, labelName+"_"+u.ID); err != nil {
		t.Fatalf("seed mail_label: %v", err)
	}
	return NewStore(conn), u.ID
}

func count(t *testing.T, st *Store, userID, label string) int {
	t.Helper()
	items, _, err := st.ListMails(userID, listFilter{Label: label, Limit: 50})
	if err != nil {
		t.Fatalf("ListMails(label=%q): %v", label, err)
	}
	return len(items)
}

// R0001/0020 root cause: the client requests the inbox by the system label NAME
// ('inbox'), but mail_label stores the per-user label_id ('inbox_<uid>'). Before the
// read-path resolver, ListMails filtered on the raw param and returned 0 even with a
// full mailbox — "메일은 오지도 않고". The name must resolve to the seeded label_id.
func TestListMailsResolvesSystemLabelName(t *testing.T) {
	st, uid := seedLabeledMail(t, "m1", "inbox")

	if got := count(t, st, uid, "inbox"); got != 1 {
		t.Fatalf("label NAME 'inbox' must resolve to the inbox mail: got %d, want 1", got)
	}
	if got := count(t, st, uid, "inbox_"+uid); got != 1 {
		t.Fatalf("concrete label_id must still match: got %d, want 1", got)
	}
	if got := count(t, st, uid, ""); got != 1 {
		t.Fatalf("no label filter lists all: got %d, want 1", got)
	}
	if got := count(t, st, uid, "bogus"); got != 0 {
		t.Fatalf("unknown label matches nothing: got %d, want 0", got)
	}
}

// The UI 'drafts' tab sends the plural; the system label name is 'draft'. The resolver
// must alias 'drafts' -> 'draft' so the drafts view is not permanently empty.
func TestListMailsResolvesDraftsAlias(t *testing.T) {
	st, uid := seedLabeledMail(t, "m1", "draft")

	if got := count(t, st, uid, "drafts"); got != 1 {
		t.Fatalf("plural 'drafts' must alias to 'draft': got %d, want 1", got)
	}
	if got := count(t, st, uid, "draft"); got != 1 {
		t.Fatalf("singular 'draft' must also resolve: got %d, want 1", got)
	}
	if got := count(t, st, uid, "inbox"); got != 0 {
		t.Fatalf("a draft must not appear under inbox: got %d, want 0", got)
	}
}

// A user-created label is addressed by its name too; the resolver must look it up in the
// label table (not just system labels).
func TestListMailsResolvesUserLabelName(t *testing.T) {
	st, uid := seedLabeledMail(t, "m1", "inbox")
	// Create a user label and attach the mail to it by its real label_id.
	lbl, err := st.CreateLabel(uid, "Work", nil)
	if err != nil {
		t.Fatalf("CreateLabel: %v", err)
	}
	if _, err := st.db.Exec(`INSERT INTO mail_label(mail_id,label_id) VALUES('m1',?)`, lbl.LabelID); err != nil {
		t.Fatalf("attach user label: %v", err)
	}
	if got := count(t, st, uid, "Work"); got != 1 {
		t.Fatalf("user-label NAME must resolve via the label table: got %d, want 1", got)
	}
	if got := count(t, st, uid, lbl.LabelID); got != 1 {
		t.Fatalf("user-label id must still match: got %d, want 1", got)
	}
}
