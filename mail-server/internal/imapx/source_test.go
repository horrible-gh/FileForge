package imapx

import (
	"bufio"
	"fmt"
	"net"
	"strings"
	"testing"
	"time"

	"mailanchor/serverd/internal/mailapi"
)

// fakeIMAP runs a scripted IMAP server on the server end of a net.Pipe. It implements
// just enough of the protocol for the incremental-fetch path (greeting, AUTHENTICATE,
// SELECT, UID SEARCH, UID FETCH, LOGOUT), letting the real client be exercised end-to-end.
func fakeIMAP(t *testing.T, serverConn net.Conn, messages map[uint32]fakeMsg, searchUIDs []uint32) {
	t.Helper()
	go func() {
		defer serverConn.Close()
		_ = serverConn.SetDeadline(time.Now().Add(5 * time.Second))
		br := bufio.NewReader(serverConn)
		fmt.Fprint(serverConn, "* OK IMAP4rev1 ready\r\n")
		for {
			line, err := br.ReadString('\n')
			if err != nil {
				return
			}
			line = strings.TrimRight(line, "\r\n")
			fields := strings.Fields(line)
			if len(fields) < 2 {
				continue
			}
			tag, verb := fields[0], strings.ToUpper(fields[1])
			switch {
			case verb == "AUTHENTICATE":
				fmt.Fprintf(serverConn, "%s OK authenticated\r\n", tag)
			case verb == "SELECT":
				fmt.Fprint(serverConn, "* OK [UIDVALIDITY 12345] ok\r\n")
				fmt.Fprintf(serverConn, "%s OK [READ-WRITE] selected\r\n", tag)
			case verb == "UID" && len(fields) >= 3 && strings.EqualFold(fields[2], "SEARCH"):
				nums := make([]string, 0, len(searchUIDs))
				for _, u := range searchUIDs {
					nums = append(nums, fmt.Sprint(u))
				}
				fmt.Fprintf(serverConn, "* SEARCH %s\r\n", strings.Join(nums, " "))
				fmt.Fprintf(serverConn, "%s OK search done\r\n", tag)
			case verb == "UID" && len(fields) >= 3 && strings.EqualFold(fields[2], "FETCH"):
				var uid uint32
				fmt.Sscanf(fields[3], "%d", &uid)
				m := messages[uid]
				flags := ""
				if m.seen {
					flags = `\Seen`
				}
				fmt.Fprintf(serverConn, "* 1 FETCH (UID %d FLAGS (%s) BODY[] {%d}\r\n", uid, flags, len(m.raw))
				fmt.Fprint(serverConn, m.raw)
				fmt.Fprint(serverConn, ")\r\n")
				fmt.Fprintf(serverConn, "%s OK fetch done\r\n", tag)
			case verb == "LOGOUT":
				fmt.Fprint(serverConn, "* BYE\r\n")
				fmt.Fprintf(serverConn, "%s OK logout\r\n", tag)
				return
			default:
				fmt.Fprintf(serverConn, "%s OK\r\n", tag)
			}
		}
	}()
}

type fakeMsg struct {
	raw  string
	seen bool
}

func msg(from, to, subject, body string) string {
	return strings.Join([]string{
		"From: " + from,
		"To: " + to,
		"Subject: " + subject,
		"Date: Sun, 21 Jun 2026 08:00:00 +0000",
		"Content-Type: text/plain; charset=utf-8",
		"", body, "",
	}, "\r\n")
}

func newPipedSource(t *testing.T, msgs map[uint32]fakeMsg, search []uint32) *Source {
	t.Helper()
	secrets := mailapi.NewMemSecretStore()
	secrets.Put("sec_1", mailapi.Credential{AccessToken: "tok", Expiry: time.Now().Add(time.Hour)})
	s := &Source{
		secrets: secrets,
		hosts:   map[string]string{"gmail": "imap.gmail.com:993"},
		dial: func(_ string) (net.Conn, error) {
			cl, srv := net.Pipe()
			fakeIMAP(t, srv, msgs, search)
			_ = cl.SetDeadline(time.Now().Add(5 * time.Second))
			return cl, nil
		},
	}
	return s
}

func acct() mailapi.ExternalAccount {
	return mailapi.ExternalAccount{AccountID: "acc_1", UserID: "u1", Email: "u@example.com",
		Provider: "gmail", OAuthRef: "sec_1"}
}

func TestFetchChangesMapsMessages(t *testing.T) {
	msgs := map[uint32]fakeMsg{
		101: {raw: msg("Alice <alice@x.com>", "u@example.com", "Hello", "plain body"), seen: true},
		102: {raw: msg("bob@x.com", "u@example.com", "Second", "second body"), seen: false},
	}
	s := newPipedSource(t, msgs, []uint32{101, 102})

	batch, err := s.FetchChanges(acct(), "", 200)
	if err != nil {
		t.Fatalf("FetchChanges: %v", err)
	}
	if len(batch.Items) != 2 {
		t.Fatalf("want 2 items, got %d", len(batch.Items))
	}
	if batch.NextCursor != "12345.102" {
		t.Fatalf("cursor=%q want 12345.102", batch.NextCursor)
	}
	first := batch.Items[0]
	if first.ExternalID != "101" || first.Subject != "Hello" || !first.IsRead {
		t.Fatalf("item0=%+v", first)
	}
	if first.From.Name != "Alice" || first.From.Address != "alice@x.com" {
		t.Fatalf("from=%+v", first.From)
	}
	if !strings.Contains(first.Body.Content, "plain body") || first.Body.Format != "text" {
		t.Fatalf("body=%+v", first.Body)
	}
	if len(first.Labels) != 1 || first.Labels[0] != "inbox" {
		t.Fatalf("labels=%v", first.Labels)
	}
	if batch.Items[1].IsRead {
		t.Fatalf("uid 102 should be unread")
	}
}

func TestFetchChangesPaginates(t *testing.T) {
	msgs := map[uint32]fakeMsg{
		101: {raw: msg("a@x.com", "u@example.com", "one", "b1")},
		102: {raw: msg("b@x.com", "u@example.com", "two", "b2")},
		103: {raw: msg("c@x.com", "u@example.com", "three", "b3")},
	}
	s := newPipedSource(t, msgs, []uint32{101, 102, 103})

	batch, err := s.FetchChanges(acct(), "", 2) // limit 2 of 3
	if err != nil {
		t.Fatalf("FetchChanges: %v", err)
	}
	if len(batch.Items) != 2 || !batch.HasMore {
		t.Fatalf("want 2 items + HasMore, got %d hasMore=%v", len(batch.Items), batch.HasMore)
	}
	if batch.NextCursor != "12345.102" {
		t.Fatalf("cursor=%q want 12345.102", batch.NextCursor)
	}
}

func TestFetchChangesUIDValidityResetIsBenign(t *testing.T) {
	// A cursor from a different UIDVALIDITY -> full resync (lastUID treated as 0).
	msgs := map[uint32]fakeMsg{101: {raw: msg("a@x.com", "u@example.com", "x", "y")}}
	s := newPipedSource(t, msgs, []uint32{101})
	batch, err := s.FetchChanges(acct(), "999.500", 200)
	if err != nil {
		t.Fatalf("FetchChanges: %v", err)
	}
	if len(batch.Items) != 1 {
		t.Fatalf("resync should refetch, got %d", len(batch.Items))
	}
}

func TestFetchChangesMissingToken(t *testing.T) {
	s := &Source{secrets: mailapi.NewMemSecretStore(), hosts: map[string]string{"gmail": "h:993"}}
	if _, err := s.FetchChanges(acct(), "", 10); err == nil {
		t.Fatal("expected error when access token absent")
	}
}

func TestFetchChangesUnknownProvider(t *testing.T) {
	s := newPipedSource(t, nil, nil)
	a := acct()
	a.Provider = "icloud"
	if _, err := s.FetchChanges(a, "", 10); err == nil {
		t.Fatal("expected error for unknown provider host")
	}
}

func TestCursorRoundTrip(t *testing.T) {
	v, u := parseCursor("12345.678")
	if v != 12345 || u != 678 {
		t.Fatalf("parseCursor=%d,%d", v, u)
	}
	if makeCursor(12345, 678) != "12345.678" {
		t.Fatalf("makeCursor=%q", makeCursor(12345, 678))
	}
	if v, u := parseCursor(""); v != 0 || u != 0 {
		t.Fatalf("empty cursor should be 0,0 got %d,%d", v, u)
	}
}

func TestExtractBodyMultipartPrefersPlain(t *testing.T) {
	raw := strings.Join([]string{
		"Content-Type: multipart/alternative; boundary=B",
		"", "--B", "Content-Type: text/html", "", "<p>html</p>",
		"--B", "Content-Type: text/plain", "", "plain wins", "--B--", "",
	}, "\r\n")
	m, err := parseMessage(raw)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	format, content := extractBody(m)
	if format != "text" || !strings.Contains(content, "plain wins") {
		t.Fatalf("extractBody=%q,%q", format, content)
	}
}
