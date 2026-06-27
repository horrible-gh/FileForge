package imapx

import (
	"bufio"
	"encoding/base64"
	"fmt"
	"net"
	"strings"
	"testing"
	"time"

	"golang.org/x/text/encoding"
	"golang.org/x/text/encoding/japanese"
	"golang.org/x/text/encoding/korean"
	"golang.org/x/text/encoding/simplifiedchinese"
	"golang.org/x/text/encoding/traditionalchinese"
	"golang.org/x/text/transform"

	"mailanchor/serverd/internal/mailapi"
)

// mustEncode transcodes a UTF-8 string into the given legacy charset for building
// realistic raw mail fixtures in tests.
func mustEncode(t *testing.T, enc encoding.Encoding, s string) []byte {
	t.Helper()
	b, _, err := transform.Bytes(enc.NewEncoder(), []byte(s))
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	return b
}

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

// TestExtractBodySinglePartBase64 is the direct R0001/NR0003 regression: a single-part
// text body declared base64 must come back decoded, not as the raw base64 string.
func TestExtractBodySinglePartBase64(t *testing.T) {
	plain := "Google 보안 알림: 새 기기에서 로그인했습니다."
	enc := base64.StdEncoding.EncodeToString([]byte(plain))
	raw := strings.Join([]string{
		"Content-Type: text/plain; charset=utf-8",
		"Content-Transfer-Encoding: base64",
		"", enc, "",
	}, "\r\n")
	m, err := parseMessage(raw)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	format, content := extractBody(m)
	if format != "text" || strings.TrimSpace(content) != plain {
		t.Fatalf("extractBody=%q,%q want %q", format, content, plain)
	}
	if strings.Contains(content, enc) {
		t.Fatalf("body still contains raw base64: %q", content)
	}
}

// TestExtractBodyBase64WrappedLines verifies that RFC 2045 line wrapping / stray
// whitespace inside the base64 payload is tolerated.
func TestExtractBodyBase64WrappedLines(t *testing.T) {
	plain := strings.Repeat("the quick brown fox jumps over the lazy dog. ", 6)
	enc := base64.StdEncoding.EncodeToString([]byte(plain))
	// Re-wrap into 76-char lines as real MTAs do.
	var wrapped strings.Builder
	for i := 0; i < len(enc); i += 76 {
		end := i + 76
		if end > len(enc) {
			end = len(enc)
		}
		wrapped.WriteString(enc[i:end])
		wrapped.WriteString("\r\n")
	}
	raw := strings.Join([]string{
		"Content-Type: text/plain; charset=utf-8",
		"Content-Transfer-Encoding: BASE64", // case-insensitive
		"", wrapped.String(),
	}, "\r\n")
	m, err := parseMessage(raw)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	_, content := extractBody(m)
	if strings.TrimSpace(content) != strings.TrimSpace(plain) {
		t.Fatalf("wrapped base64 not decoded: got %q", content)
	}
}

// TestExtractBodyMultipartBase64Part verifies a base64 text/plain part within a
// multipart message is decoded (stdlib multipart does NOT auto-decode base64).
func TestExtractBodyMultipartBase64Part(t *testing.T) {
	plain := "decoded multipart body"
	enc := base64.StdEncoding.EncodeToString([]byte(plain))
	raw := strings.Join([]string{
		"Content-Type: multipart/alternative; boundary=B",
		"", "--B", "Content-Type: text/html", "", "<p>html</p>",
		"--B",
		"Content-Type: text/plain; charset=utf-8",
		"Content-Transfer-Encoding: base64",
		"", enc,
		"--B--", "",
	}, "\r\n")
	m, err := parseMessage(raw)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	format, content := extractBody(m)
	if format != "text" || strings.TrimSpace(content) != plain {
		t.Fatalf("extractBody=%q,%q want %q", format, content, plain)
	}
}

// TestExtractBodySinglePartQuotedPrintable verifies the single-part quoted-printable
// path (net/mail does NOT decode the single-part body at all).
func TestExtractBodySinglePartQuotedPrintable(t *testing.T) {
	raw := strings.Join([]string{
		"Content-Type: text/plain; charset=utf-8",
		"Content-Transfer-Encoding: quoted-printable",
		"", "caf=C3=A9 =E2=82=AC soft=20break=", "continued", "",
	}, "\r\n")
	m, err := parseMessage(raw)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	_, content := extractBody(m)
	if !strings.Contains(content, "café") || !strings.Contains(content, "€") {
		t.Fatalf("quoted-printable not decoded: %q", content)
	}
	if strings.Contains(content, "=C3=A9") {
		t.Fatalf("body still contains raw QP escapes: %q", content)
	}
}

// TestDecodeCTEMalformedFallsBack ensures a malformed payload degrades to the raw
// bytes rather than vanishing into an empty body.
func TestDecodeCTEMalformedFallsBack(t *testing.T) {
	bad := []byte("!!!not base64!!!")
	if got := decodeCTE("base64", bad); string(got) != string(bad) {
		t.Fatalf("malformed base64 should fall back to raw, got %q", got)
	}
	if got := decodeCTE("7bit", []byte("plain")); string(got) != "plain" {
		t.Fatalf("identity CTE changed payload: %q", got)
	}
}

// TestDecodeCharsetLatin1 verifies the single-byte Latin-1 transcode path.
func TestDecodeCharsetLatin1(t *testing.T) {
	// 0xE9 is 'é' in ISO-8859-1.
	if got := decodeCharset("iso-8859-1", []byte{0x63, 0x61, 0x66, 0xE9}); got != "café" {
		t.Fatalf("latin1 transcode=%q want café", got)
	}
	if got := decodeCharset("utf-8", []byte("café")); got != "café" {
		t.Fatalf("utf-8 passthrough=%q", got)
	}
}

// TestDecodeCharsetMultibyte is the core of this rework: every multi-byte legacy charset
// real mail uses must round-trip back to readable UTF-8, not mojibake. Without x/text
// these all fell through to a raw byte pass and surfaced as garbage (the rejected
// "only show part" behavior).
func TestDecodeCharsetMultibyte(t *testing.T) {
	cases := []struct {
		name    string
		charset string
		enc     encoding.Encoding
		text    string
	}{
		{"shift_jis", "Shift_JIS", japanese.ShiftJIS, "こんにちは世界"},
		{"shift_jis-alias-sjis", "sjis", japanese.ShiftJIS, "日本語メール"},
		{"euc-jp", "EUC-JP", japanese.EUCJP, "メールの本文です"},
		{"iso-2022-jp", "ISO-2022-JP", japanese.ISO2022JP, "セキュリティ通知"},
		{"euc-kr", "EUC-KR", korean.EUCKR, "안녕하세요 세계"},
		{"gbk", "GBK", simplifiedchinese.GBK, "你好，世界"},
		{"gb18030", "gb18030", simplifiedchinese.GB18030, "中文邮件正文"},
		{"big5", "Big5", traditionalchinese.Big5, "繁體中文郵件"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			raw := mustEncode(t, tc.enc, tc.text)
			if string(raw) == tc.text {
				t.Fatalf("fixture not actually re-encoded for %s", tc.charset)
			}
			got := decodeCharset(tc.charset, raw)
			if got != tc.text {
				t.Fatalf("decodeCharset(%q)=%q want %q", tc.charset, got, tc.text)
			}
		})
	}
}

// TestExtractBodyShiftJISBase64 exercises the realistic Japanese-mail path end-to-end:
// a Shift_JIS body that is then base64-encoded (charset + CTE compose), which is exactly
// the combination that produced R0001's unreadable output before this fix.
func TestExtractBodyShiftJISBase64(t *testing.T) {
	plain := "Google セキュリティ通知: 新しいデバイスでログインしました。"
	sjis := mustEncode(t, japanese.ShiftJIS, plain)
	enc := base64.StdEncoding.EncodeToString(sjis)
	raw := strings.Join([]string{
		"Content-Type: text/plain; charset=Shift_JIS",
		"Content-Transfer-Encoding: base64",
		"", enc, "",
	}, "\r\n")
	m, err := parseMessage(raw)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	format, content := extractBody(m)
	if format != "text" || strings.TrimSpace(content) != plain {
		t.Fatalf("extractBody=%q,%q want %q", format, content, plain)
	}
}

// TestExtractBodyISO2022JPQuotedPrintable exercises ISO-2022-JP (the dominant Japanese
// email charset) carried as quoted-printable through the multipart text/plain path.
func TestExtractBodyISO2022JPQuotedPrintable(t *testing.T) {
	plain := "件名のテスト"
	jis := mustEncode(t, japanese.ISO2022JP, plain)
	// quoted-printable-encode the ISO-2022-JP bytes (escape every non-printable byte).
	var qp strings.Builder
	for _, b := range jis {
		if b >= 0x20 && b < 0x7f && b != '=' {
			qp.WriteByte(b)
		} else {
			fmt.Fprintf(&qp, "=%02X", b)
		}
	}
	raw := strings.Join([]string{
		"Content-Type: text/plain; charset=ISO-2022-JP",
		"Content-Transfer-Encoding: quoted-printable",
		"", qp.String(), "",
	}, "\r\n")
	m, err := parseMessage(raw)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	_, content := extractBody(m)
	if strings.TrimSpace(content) != plain {
		t.Fatalf("iso-2022-jp body=%q want %q", content, plain)
	}
}

// TestDecodeCharsetUnknownDegradesGracefully ensures an unresolvable charset still
// yields visible (Latin-1-mapped) text rather than an empty body.
func TestDecodeCharsetUnknownDegradesGracefully(t *testing.T) {
	if got := decodeCharset("x-totally-made-up", []byte{0x68, 0x69, 0xE9}); got != "hié" {
		t.Fatalf("unknown charset fallback=%q want hié", got)
	}
}

// TestDecodeStoredBody covers the header-less backfill decoder used to repair bodies that
// were persisted raw before extractBody decoded them (R0001 / NR0003). The critical
// safety property is that genuine plaintext is never mistaken for base64 and rewritten.
func TestDecodeStoredBody(t *testing.T) {
	// A realistic nested case: base64 wrapping an ISO-2022-JP Japanese body.
	jp := "メール" // "mail"
	isoJP := mustEncode(t, japanese.ISO2022JP, jp)
	b64WrappingISO := base64.StdEncoding.EncodeToString(isoJP)

	cases := []struct {
		name    string
		in      string
		want    string
		changed bool
	}{
		// --- must be left untouched ---
		{"plaintext the user verified as good", "test111\r\n123\r\n", "test111\r\n123\r\n", false},
		{"empty", "", "", false},
		{"whitespace only", "  \r\n ", "  \r\n ", false},
		{"already readable utf8", "Hello, 世界", "Hello, 世界", false},
		{"short non-multiple-of-4 token", "test111123", "test111123", false},
		// --- must be decoded ---
		{"raw base64 the user flagged", "dGVzdA==\r\n", "test", true},
		{"raw base64 digits", "MTIzNA==", "1234", true},
		{"line-wrapped base64", base64.StdEncoding.EncodeToString([]byte("a longer plain body that was stored base64\n")), "a longer plain body that was stored base64\n", true},
		{"base64 wrapping iso-2022-jp", b64WrappingISO, jp, true},
		{"raw iso-2022-jp escapes", string(isoJP), jp, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, changed := DecodeStoredBody(tc.in)
			if got != tc.want || changed != tc.changed {
				t.Fatalf("DecodeStoredBody(%q) = (%q, %v) want (%q, %v)", tc.in, got, changed, tc.want, tc.changed)
			}
		})
	}
}

// TestDecodeStoredBodyLeavesNonTextBase64 ensures a string that decodes as base64 but to
// non-UTF-8 bytes (with no ISO-2022-JP escapes) is left as-is rather than mangled.
func TestDecodeStoredBodyLeavesNonTextBase64(t *testing.T) {
	in := base64.StdEncoding.EncodeToString([]byte{0xff, 0xfe, 0xfd, 0xfc})
	got, changed := DecodeStoredBody(in)
	if changed || got != in {
		t.Fatalf("non-text base64 should be untouched, got (%q, %v)", got, changed)
	}
}

// TestBackfillSnippetFromStoredBody reproduces the 0021 TR0008 rejection: opening a mail
// was fixed (body_content), but the mail *list* still rendered a snippet frozen from the
// raw body (base64 / untranscoded ISO-2022-JP). The backfill rebuilds the snippet from the
// re-decoded body with mailapi.MakeSnippet — this asserts that composition yields clean,
// human-readable text with no base64 run and no ISO-2022-JP escape bytes left over.
func TestBackfillSnippetFromStoredBody(t *testing.T) {
	jpUTF8 := "へようこそ"
	// raw ISO-2022-JP bytes for jpUTF8, exactly as an undecoded body would have been stored.
	rawJISBytes, err := japanese.ISO2022JP.NewEncoder().Bytes([]byte(jpUTF8))
	if err != nil {
		t.Fatalf("encode iso-2022-jp fixture: %v", err)
	}
	rawJIS := string(rawJISBytes)
	cases := []struct {
		name      string
		storedRaw string // what an old row had in BOTH body_content and snippet
		wantSnip  string
	}{
		{"raw base64 body", "dGVzdA==", "test"},
		{"raw iso2022jp body", rawJIS, jpUTF8},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			decoded, changed := DecodeStoredBody(tc.storedRaw)
			if !changed {
				t.Fatalf("expected stored raw body %q to be re-decoded", tc.storedRaw)
			}
			snip := mailapi.MakeSnippet(decoded)
			if snip != tc.wantSnip {
				t.Fatalf("regenerated snippet = %q, want %q", snip, tc.wantSnip)
			}
			// The old (stale) snippet rebuilt from the raw bytes must NOT survive.
			if stale := mailapi.MakeSnippet(tc.storedRaw); stale == snip {
				t.Fatalf("raw-derived snippet %q should differ from decoded snippet", stale)
			}
			if strings.ContainsAny(snip, "\x1b") {
				t.Fatalf("snippet still contains ISO-2022-JP escape: %q", snip)
			}
		})
	}
}
