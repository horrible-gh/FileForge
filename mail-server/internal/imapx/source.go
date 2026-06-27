// Package imapx is the IMAP adapter behind mailapi.ChangeSource. It performs an
// incremental inbox fetch over a TLS IMAP connection using the stdlib (crypto/tls,
// bufio, net/mail) plus golang.org/x/text for body charset transcoding — the same
// x/-family policy already used here (golang.org/x/crypto). x/text is required so a
// mailbox body in any IANA charset (UTF-8, Latin-1, and the multi-byte legacy
// charsets real mail uses — ISO-2022-JP, Shift_JIS, EUC-JP, EUC-KR, GBK, Big5,
// windows-125x, …) is delivered to the client as readable UTF-8, not mojibake
// (R0001 / NR0003). Authentication is SASL XOAUTH2, presenting the per-account OAuth
// access token resolved from the SecretStore (so it composes with the oauthx exchanger).
//
// Scope (the concrete real adapter): OAuth/XOAUTH2 providers (gmail/outlook). The
// incremental cursor is "UIDVALIDITY.lastUID"; each run SELECTs INBOX, UID SEARCHes
// for UIDs above the cursor, fetches a bounded page, and maps each message to an
// upsert ExternalChange. Upstream deletions (require CONDSTORE/QRESYNC) and attachment
// byte download remain L0013 DEFERRED ("provider-specific change-fetch API differences"); password-IMAP
// host plumbing (no XOAUTH2) is the remaining provider-specific extension.
package imapx

import (
	"bytes"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
	"mime/quotedprintable"
	"net"
	"net/mail"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"golang.org/x/text/encoding"
	"golang.org/x/text/encoding/charmap"
	"golang.org/x/text/encoding/ianaindex"
	"golang.org/x/text/encoding/japanese"
	"golang.org/x/text/encoding/korean"
	"golang.org/x/text/encoding/simplifiedchinese"
	"golang.org/x/text/encoding/traditionalchinese"
	"golang.org/x/text/transform"

	"mailanchor/serverd/internal/mailapi"
)

// hostFor maps an OAuth provider to its IMAP endpoint (XOAUTH2).
var defaultHosts = map[string]string{
	"gmail":   "imap.gmail.com:993",
	"outlook": "outlook.office365.com:993",
}

// Source implements mailapi.ChangeSource against XOAUTH2 IMAP providers.
type Source struct {
	secrets mailapi.SecretStore
	hosts   map[string]string
	dial    func(addr string) (net.Conn, error) // overridable for tests
}

// New builds a Source resolving access tokens from secrets. Host overrides may be passed
// (nil -> built-in gmail/outlook endpoints).
func New(secrets mailapi.SecretStore, hostOverrides map[string]string) *Source {
	hosts := map[string]string{}
	for k, v := range defaultHosts {
		hosts[k] = v
	}
	for k, v := range hostOverrides {
		hosts[k] = v
	}
	return &Source{
		secrets: secrets,
		hosts:   hosts,
		dial: func(addr string) (net.Conn, error) {
			host, _, err := net.SplitHostPort(addr)
			if err != nil {
				return nil, err
			}
			return tls.DialWithDialer(&net.Dialer{Timeout: 20 * time.Second}, "tcp", addr,
				&tls.Config{ServerName: host})
		},
	}
}

// FetchChanges fetches one bounded page of inbox upserts above the cursor.
func (s *Source) FetchChanges(account mailapi.ExternalAccount, cursor string, limit int) (mailapi.ChangeBatch, error) {
	addr, ok := s.hosts[account.Provider]
	if !ok {
		return mailapi.ChangeBatch{}, fmt.Errorf("imapx: no IMAP host for provider %q", account.Provider)
	}
	if account.OAuthRef == "" || s.secrets == nil {
		return mailapi.ChangeBatch{}, errors.New("imapx: account has no OAuth credential")
	}
	cred, ok := s.secrets.Get(account.OAuthRef)
	if !ok || cred.AccessToken == "" {
		return mailapi.ChangeBatch{}, errors.New("imapx: missing access token")
	}
	if limit <= 0 {
		limit = 200
	}

	conn, err := s.dial(addr)
	if err != nil {
		return mailapi.ChangeBatch{}, fmt.Errorf("imapx: dial %s: %w", addr, err)
	}
	c := newClient(conn)
	defer c.close()

	if err := c.authXOAuth2(account.Email, cred.AccessToken); err != nil {
		return mailapi.ChangeBatch{}, err
	}
	uidValidity, err := c.selectInbox()
	if err != nil {
		return mailapi.ChangeBatch{}, err
	}

	prevValidity, lastUID := parseCursor(cursor)
	if prevValidity != 0 && prevValidity != uidValidity {
		lastUID = 0 // mailbox re-created upstream -> full resync (L0013 §2.3 reset)
	}

	uids, err := c.searchUIDsAbove(lastUID)
	if err != nil {
		return mailapi.ChangeBatch{}, err
	}
	sort.Slice(uids, func(i, j int) bool { return uids[i] < uids[j] })

	hasMore := false
	if len(uids) > limit {
		uids = uids[:limit]
		hasMore = true
	}
	if len(uids) == 0 {
		return mailapi.ChangeBatch{NextCursor: makeCursor(uidValidity, lastUID), HasMore: false}, nil
	}

	items := make([]mailapi.ExternalChange, 0, len(uids))
	maxUID := lastUID
	for _, uid := range uids {
		msg, seen, err := c.fetchMessage(uid)
		if err != nil {
			return mailapi.ChangeBatch{}, err
		}
		ch, err := mapMessage(uid, msg, seen)
		if err != nil {
			// A single unparseable message must not abort the whole page; skip it but
			// still advance the cursor past it so we do not loop on it forever.
			if uid > maxUID {
				maxUID = uid
			}
			continue
		}
		items = append(items, ch)
		if uid > maxUID {
			maxUID = uid
		}
	}

	return mailapi.ChangeBatch{
		Items:      items,
		NextCursor: makeCursor(uidValidity, maxUID),
		HasMore:    hasMore,
	}, nil
}

// --- cursor helpers ---

func parseCursor(cursor string) (uidValidity, lastUID uint32) {
	parts := strings.SplitN(cursor, ".", 2)
	if len(parts) != 2 {
		return 0, 0
	}
	v, _ := strconv.ParseUint(parts[0], 10, 32)
	u, _ := strconv.ParseUint(parts[1], 10, 32)
	return uint32(v), uint32(u)
}

func makeCursor(uidValidity, lastUID uint32) string {
	return strconv.FormatUint(uint64(uidValidity), 10) + "." + strconv.FormatUint(uint64(lastUID), 10)
}

// --- message mapping ---

// parseMessage parses raw RFC 5322 bytes into a mail.Message.
func parseMessage(raw string) (*mail.Message, error) {
	return mail.ReadMessage(strings.NewReader(raw))
}

// mapMessage parses a fetched RFC 5322 message into an upsert ExternalChange.
func mapMessage(uid uint32, raw []byte, seen bool) (mailapi.ExternalChange, error) {
	m, err := parseMessage(string(raw))
	if err != nil {
		return mailapi.ExternalChange{}, err
	}
	dec := new(mime.WordDecoder)
	subject, _ := dec.DecodeHeader(m.Header.Get("Subject"))

	from := firstAddress(m.Header.Get("From"))
	to := addressList(m.Header.Get("To"))
	cc := addressList(m.Header.Get("Cc"))

	received := time.Now().UTC()
	if d, derr := m.Header.Date(); derr == nil {
		received = d.UTC()
	}

	format, content := extractBody(m)

	return mailapi.ExternalChange{
		Kind: mailapi.ChangeUpsert,
		// Prefer the stable RFC 5322 Message-ID as the dedup identity. The UID is only an
		// incremental-fetch cursor and is NOT stable: a UIDVALIDITY reset re-assigns UIDs,
		// so a UID-based external_ref would create duplicate rows and reset is_read on the
		// re-fetched messages (NR0011 B4). Message-ID survives that; fall back to the UID
		// only when the header is absent.
		ExternalID: externalRef(uid, m.Header.Get("Message-Id")),
		From:       from,
		To:         to,
		CC:         cc,
		Subject:    subject,
		Body:       mailapi.Body{Format: format, Content: content},
		ReceivedAt: received.Format(time.RFC3339),
		IsRead:     seen,
		// An INBOX-only fetch sees only the "inbox" membership, not the user's full label
		// set — mark partial so the merge does not wipe sent/draft/user labels (B3).
		Labels:        []string{"inbox"},
		LabelsPartial: true,
	}, nil
}

// externalRef returns the stable dedup key: the normalized Message-ID if present, else
// the UID as a string (NR0011 B4).
func externalRef(uid uint32, messageID string) string {
	id := strings.TrimSpace(messageID)
	id = strings.TrimPrefix(id, "<")
	id = strings.TrimSuffix(id, ">")
	id = strings.TrimSpace(id)
	if id != "" {
		return "mid:" + id
	}
	return strconv.FormatUint(uint64(uid), 10)
}

func firstAddress(header string) mailapi.Address {
	as := addressList(header)
	if len(as) == 0 {
		return mailapi.Address{}
	}
	return as[0]
}

func addressList(header string) []mailapi.Address {
	if strings.TrimSpace(header) == "" {
		return nil
	}
	parsed, err := mail.ParseAddressList(header)
	if err != nil || len(parsed) == 0 {
		return nil
	}
	out := make([]mailapi.Address, 0, len(parsed))
	for _, a := range parsed {
		out = append(out, mailapi.Address{Name: a.Name, Address: a.Address})
	}
	return out
}

// extractBody returns (format, content). For multipart messages it prefers the first
// text/plain part, then text/html; for single-part it uses the declared text subtype.
// Rich HTML rendering and attachment extraction are downstream concerns (DEFERRED).
//
// Each payload is run through decodeBody so the Content-Transfer-Encoding is reversed
// (and the declared charset best-effort transcoded) before it reaches the client. Go's
// net/mail leaves the single-part body completely raw, and mime/multipart only
// transparently decodes quoted-printable parts — base64 parts arrive raw — so without
// this step a base64-encoded message body surfaces to the client as an unreadable
// base64 string (R0001 / NR0003).
func extractBody(m *mail.Message) (format, content string) {
	ctype := m.Header.Get("Content-Type")
	mediaType, params, err := mime.ParseMediaType(ctype)
	if err != nil || !strings.HasPrefix(mediaType, "multipart/") {
		raw, _ := io.ReadAll(io.LimitReader(m.Body, 1<<20))
		body := decodeBody(m.Header.Get("Content-Transfer-Encoding"), params["charset"], raw)
		if strings.HasPrefix(mediaType, "text/html") {
			return "html", body
		}
		return "text", body
	}
	boundary := params["boundary"]
	if boundary == "" {
		raw, _ := io.ReadAll(io.LimitReader(m.Body, 1<<20))
		return "text", decodeBody(m.Header.Get("Content-Transfer-Encoding"), params["charset"], raw)
	}
	mr := multipart.NewReader(m.Body, boundary)
	var htmlBody string
	for {
		part, perr := mr.NextPart()
		if perr != nil {
			break
		}
		pType, pParams, _ := mime.ParseMediaType(part.Header.Get("Content-Type"))
		raw, _ := io.ReadAll(io.LimitReader(part, 1<<20))
		// multipart transparently decodes (and hides) a quoted-printable CTE, so a part
		// whose header still reports an encoding here is one stdlib did not unwrap (base64).
		data := decodeBody(part.Header.Get("Content-Transfer-Encoding"), pParams["charset"], raw)
		switch {
		case strings.HasPrefix(pType, "text/plain"):
			return "text", data // plain wins
		case strings.HasPrefix(pType, "text/html") && htmlBody == "":
			htmlBody = data
		}
	}
	if htmlBody != "" {
		return "html", htmlBody
	}
	return "text", ""
}

// decodeBody turns a raw body payload into a UTF-8 string by (1) reversing the
// Content-Transfer-Encoding and (2) transcoding the declared charset to UTF-8.
func decodeBody(cte, charset string, raw []byte) string {
	return decodeCharset(charset, decodeCTE(cte, raw))
}

// decodeCTE reverses a Content-Transfer-Encoding. Only "base64" and "quoted-printable"
// carry a non-identity transformation; any other value (7bit/8bit/binary/empty) returns
// the bytes unchanged. On a decode error the raw bytes are returned so a malformed
// encoding degrades to (ugly but) visible text rather than a silently empty body.
func decodeCTE(encoding string, raw []byte) []byte {
	switch strings.ToLower(strings.TrimSpace(encoding)) {
	case "base64":
		// RFC 2045 base64 is line-wrapped and may carry stray whitespace; base64 has no
		// significant whitespace, so strip it all before decoding.
		clean := strings.Map(func(r rune) rune {
			if r == '\r' || r == '\n' || r == ' ' || r == '\t' {
				return -1
			}
			return r
		}, string(raw))
		if dec, err := base64.StdEncoding.DecodeString(clean); err == nil {
			return dec
		}
		// Tolerate missing padding (some senders omit it).
		if dec, err := base64.RawStdEncoding.DecodeString(strings.TrimRight(clean, "=")); err == nil {
			return dec
		}
		return raw
	case "quoted-printable":
		if dec, err := io.ReadAll(quotedprintable.NewReader(bytes.NewReader(raw))); err == nil {
			return dec
		}
		return raw
	default:
		return raw
	}
}

// decodeCharset transcodes decoded bytes to UTF-8 for any IANA-registered charset.
// UTF-8/US-ASCII pass straight through (already UTF-8); every other declared charset —
// single-byte (ISO-8859-x, windows-125x, KOI8) and multi-byte legacy (ISO-2022-JP,
// Shift_JIS, EUC-JP, EUC-KR, GBK/GB2312, GB18030, Big5, …) — is resolved through
// golang.org/x/text and decoded to UTF-8. This is the whole point of the fix: real mail,
// especially Japanese/CJK, arrives in these charsets and must render as readable text,
// not mojibake. On any failure the body degrades gracefully (Latin-1 byte map, then raw)
// so a charset we cannot resolve still yields visible text rather than an empty body.
func decodeCharset(charset string, b []byte) string {
	cs := strings.ToLower(strings.TrimSpace(charset))
	if cs == "" || cs == "utf-8" || cs == "utf8" || cs == "us-ascii" || cs == "ascii" {
		// Already UTF-8 (ASCII is a UTF-8 subset); decoding via a UTF-8 decoder would only
		// risk replacing bytes, so pass through unchanged.
		return string(b)
	}

	enc := lookupEncoding(charset)
	if enc != nil {
		if decoded, _, err := transform.Bytes(enc.NewDecoder(), b); err == nil {
			return string(decoded)
		}
	}

	// Unknown/unresolvable charset: map bytes 1:1 as Latin-1 so single-byte text stays
	// legible, falling back to the raw bytes only if even that is empty.
	var sb strings.Builder
	sb.Grow(len(b))
	for _, c := range b {
		sb.WriteRune(rune(c))
	}
	if sb.Len() > 0 {
		return sb.String()
	}
	return string(b)
}

// DecodeStoredBody reverses an *already-stored* body that was persisted before the
// extractBody decode step existed (R0001 / NR0003 backfill). Unlike the receive-time
// path it has no MIME headers to consult — the Content-Transfer-Encoding and charset
// were lost when only the (raw) payload was saved — so it detects the encoding from the
// stored bytes themselves. It is deliberately conservative: it transforms a row ONLY
// when it can confidently recover readable UTF-8, and returns changed=false otherwise,
// so a one-time bulk re-decode never corrupts bodies that were already stored correctly.
//
// Two recoverable shapes occur in the wild (and in the live DB):
//
//  1. A raw base64 payload (CTE was base64, stdlib never unwrapped it): e.g. "dGVzdA=="
//     -> "test". Detected by a strict base64 shape (whitespace-insignificant alphabet,
//     length a multiple of 4, ≥ minBackfillB64Len) whose decode is valid UTF-8 (or itself
//     ISO-2022-JP, the common nested case where base64 wraps a Japanese body).
//  2. A raw ISO-2022-JP payload (7-bit escape sequences sitting in the body untranscoded):
//     transcoded to UTF-8.
//
// Anything that does not match — plaintext (incl. short tokens like "test111\r\n123" that
// are NOT valid-length base64), bodies that base64-decode to non-text, or bodies already
// valid UTF-8 with no escapes — is returned unchanged with changed=false.
func DecodeStoredBody(stored string) (decoded string, changed bool) {
	if strings.TrimSpace(stored) == "" {
		return stored, false
	}

	// (1) Strict header-less base64 detection.
	if clean, ok := strictBase64(stored); ok {
		if dec, err := base64.StdEncoding.DecodeString(clean); err == nil {
			if bytes.Contains(dec, []byte("\x1b$")) || bytes.Contains(dec, []byte("\x1b(")) {
				// base64 wrapping an ISO-2022-JP body — transcode the inner bytes.
				if s, ok := transcodeISO2022JP(dec); ok {
					return s, true
				}
			}
			if utf8.Valid(dec) {
				return string(dec), true
			}
			// Decodes, but not to text we can vouch for — leave the row untouched rather
			// than replacing a base64 string with mojibake.
			return stored, false
		}
	}

	// (2) Raw ISO-2022-JP escape sequences sitting untranscoded in the stored text.
	if strings.Contains(stored, "\x1b$") || strings.Contains(stored, "\x1b(") {
		// ISO-2022-JP is 7-bit, so the bytes survived the TEXT column 1:1.
		if s, ok := transcodeISO2022JP([]byte(stored)); ok {
			return s, true
		}
	}

	return stored, false
}

// minBackfillB64Len is the shortest cleaned base64 run we will treat as an encoded body.
// 8 covers the real short payloads in the DB ("dGVzdA==" -> "test", "MTIzNA==" -> "1234")
// while the length-multiple-of-4 rule already rejects readable tokens like "test111123".
const minBackfillB64Len = 8

// strictBase64 reports whether s is plausibly a standalone base64 body and returns the
// whitespace-stripped form ready to decode. The rules are intentionally tight (proper
// length, canonical alphabet, no stray characters) so plaintext is never mistaken for
// base64 during the backfill sweep.
func strictBase64(s string) (clean string, ok bool) {
	clean = strings.Map(func(r rune) rune {
		if r == '\r' || r == '\n' || r == ' ' || r == '\t' {
			return -1
		}
		return r
	}, s)
	if len(clean) < minBackfillB64Len || len(clean)%4 != 0 {
		return "", false
	}
	for i, r := range clean {
		isB64 := (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') ||
			(r >= '0' && r <= '9') || r == '+' || r == '/'
		if isB64 {
			continue
		}
		// '=' padding is only legal in the final one or two positions.
		if r == '=' && i >= len(clean)-2 {
			continue
		}
		return "", false
	}
	return clean, true
}

// transcodeISO2022JP decodes ISO-2022-JP bytes to UTF-8, returning ok=false (so the
// caller leaves the row unchanged) if the bytes are not valid ISO-2022-JP.
func transcodeISO2022JP(b []byte) (string, bool) {
	dec, _, err := transform.Bytes(japanese.ISO2022JP.NewDecoder(), b)
	if err != nil || !utf8.Valid(dec) {
		return "", false
	}
	return string(dec), true
}

// lookupEncoding resolves an IANA charset name (and common aliases) to an x/text
// encoding. It tries the MIME registry first (the names that appear in Content-Type
// headers), then the broader IANA registry, then a small alias table for spellings the
// registries miss. Returns nil when nothing matches.
func lookupEncoding(charset string) encoding.Encoding {
	if enc, err := ianaindex.MIME.Encoding(charset); err == nil && enc != nil {
		return enc
	}
	if enc, err := ianaindex.IANA.Encoding(charset); err == nil && enc != nil {
		return enc
	}
	switch strings.ToLower(strings.TrimSpace(charset)) {
	case "iso-8859-1", "iso8859-1", "iso_8859-1", "latin1", "latin-1", "cp819", "8859-1":
		return charmap.ISO8859_1
	case "shift-jis", "shiftjis", "sjis", "ms_kanji", "cp932", "windows-31j":
		return japanese.ShiftJIS
	case "euc-jp", "eucjp", "x-euc-jp":
		return japanese.EUCJP
	case "iso-2022-jp", "iso2022jp", "csiso2022jp":
		return japanese.ISO2022JP
	case "euc-kr", "euckr", "ks_c_5601-1987", "cp949", "uhc":
		return korean.EUCKR
	case "gb2312", "gbk", "cp936", "csgbk":
		return simplifiedchinese.GBK
	case "gb18030":
		return simplifiedchinese.GB18030
	case "big5", "big-5", "cp950", "csbig5":
		return traditionalchinese.Big5
	}
	return nil
}
