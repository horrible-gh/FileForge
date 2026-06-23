// Package imapx is the IMAP adapter behind mailapi.ChangeSource. It performs an
// incremental inbox fetch over a TLS IMAP connection using only the stdlib
// (crypto/tls, bufio, net/mail) — no new dependency, same ethos as the smtpx SMTP
// adapter. Authentication is SASL XOAUTH2, presenting the per-account OAuth access
// token resolved from the SecretStore (so it composes with the oauthx exchanger).
//
// Scope (the concrete real adapter): OAuth/XOAUTH2 providers (gmail/outlook). The
// incremental cursor is "UIDVALIDITY.lastUID"; each run SELECTs INBOX, UID SEARCHes
// for UIDs above the cursor, fetches a bounded page, and maps each message to an
// upsert ExternalChange. Upstream deletions (require CONDSTORE/QRESYNC) and attachment
// byte download remain L0013 DEFERRED ("외부 제공자별 변경 페치 API 차이"); password-IMAP
// host plumbing (no XOAUTH2) is the remaining provider-specific extension.
package imapx

import (
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
	"net"
	"net/mail"
	"sort"
	"strconv"
	"strings"
	"time"

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
func extractBody(m *mail.Message) (format, content string) {
	ctype := m.Header.Get("Content-Type")
	mediaType, params, err := mime.ParseMediaType(ctype)
	if err != nil || !strings.HasPrefix(mediaType, "multipart/") {
		body, _ := io.ReadAll(io.LimitReader(m.Body, 1<<20))
		if strings.HasPrefix(mediaType, "text/html") {
			return "html", string(body)
		}
		return "text", string(body)
	}
	boundary := params["boundary"]
	if boundary == "" {
		body, _ := io.ReadAll(io.LimitReader(m.Body, 1<<20))
		return "text", string(body)
	}
	mr := multipart.NewReader(m.Body, boundary)
	var htmlBody string
	for {
		part, perr := mr.NextPart()
		if perr != nil {
			break
		}
		pType, _, _ := mime.ParseMediaType(part.Header.Get("Content-Type"))
		data, _ := io.ReadAll(io.LimitReader(part, 1<<20))
		switch {
		case strings.HasPrefix(pType, "text/plain"):
			return "text", string(data) // plain wins
		case strings.HasPrefix(pType, "text/html") && htmlBody == "":
			htmlBody = string(data)
		}
	}
	if htmlBody != "" {
		return "html", htmlBody
	}
	return "text", ""
}
