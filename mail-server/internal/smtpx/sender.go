// Package smtpx is the SMTP adapter behind mailapi.Sender. It builds an RFC 5322 /
// MIME message from the composed mail (resolving attachment bytes via the Blob store)
// and delivers it through either a configured relay or Gmail's SMTP XOAUTH2 endpoint
// using the OAuth token already held for the connected account.
package smtpx

import (
	"bytes"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
	"net/mail"
	"net/smtp"
	"net/textproto"
	"strings"
	"time"

	"mailanchor/serverd/internal/mailapi"
	"mailanchor/serverd/internal/retry"
	"mailanchor/serverd/internal/storage"
)

const (
	gmailSMTPAddr      = "smtp.gmail.com:587"
	oauthRefreshMargin = 5 * time.Minute
)

// Sender delivers through Gmail OAuth SMTP when the account has a Gmail OAuth ref,
// otherwise through the configured relay (host:port + optional auth).
type Sender struct {
	Addr      string    // relay host:port; empty means relay fallback is disabled
	Auth      smtp.Auth // nil for unauthenticated relays
	Blob      storage.Blob
	Secrets   mailapi.SecretStore
	OAuth     mailapi.OAuthExchanger
	GmailAddr string // test override; empty -> smtp.gmail.com:587
	Now       func() time.Time
}

// New builds a relay Sender. If username is empty, no auth is used.
func New(host string, port int, username, password string, blob storage.Blob) *Sender {
	var auth smtp.Auth
	if username != "" {
		auth = smtp.PlainAuth("", username, password, host)
	}
	return &Sender{Addr: fmt.Sprintf("%s:%d", host, port), Auth: auth, Blob: blob}
}

// NewWithOAuth builds a Sender that can use Gmail OAuth SMTP and optionally fall back to
// a configured relay for non-Gmail/password accounts.
func NewWithOAuth(host string, port int, username, password string, secrets mailapi.SecretStore, oauth mailapi.OAuthExchanger, blob storage.Blob) *Sender {
	s := New(host, port, username, password, blob)
	if host == "" {
		s.Addr = ""
		s.Auth = nil
	}
	s.Secrets = secrets
	s.OAuth = oauth
	return s
}

// Send composes the MIME message and hands it to the relay (mailapi.Sender).
func (s *Sender) Send(acc mailapi.ExternalAccount, m mailapi.OutgoingMail) error {
	msg, err := s.build(m)
	if err != nil {
		return err
	}
	rcpts := make([]string, 0, len(m.To)+len(m.CC)+len(m.BCC))
	for _, g := range [][]mailapi.Address{m.To, m.CC, m.BCC} {
		for _, a := range g {
			rcpts = append(rcpts, a.Address)
		}
	}
	if acc.Provider == "gmail" && acc.OAuthRef != "" && s.Secrets != nil {
		return s.sendGmailXOAUTH2(acc, m.From.Address, rcpts, msg)
	}
	if s.Addr == "" {
		return errors.New("sender not configured")
	}
	return smtp.SendMail(s.Addr, s.Auth, m.From.Address, rcpts, msg)
}

func (s *Sender) sendGmailXOAUTH2(acc mailapi.ExternalAccount, from string, rcpts []string, msg []byte) error {
	cred, ok := s.Secrets.Get(acc.OAuthRef)
	if !ok || cred.AccessToken == "" {
		return retry.Permanent(mailapi.ErrOAuthCredentialMissing)
	}
	if needsRefresh(s.now(), cred) && s.OAuth != nil && cred.RefreshToken != "" {
		refreshed, err := s.OAuth.Refresh(acc.Provider, cred.RefreshToken)
		if err != nil {
			return err
		}
		cred = refreshed
		s.Secrets.Put(acc.OAuthRef, cred)
	}
	addr := s.GmailAddr
	if addr == "" {
		addr = gmailSMTPAddr
	}
	return sendSMTPStartTLS(addr, xoauth2Auth{username: acc.Email, accessToken: cred.AccessToken}, from, rcpts, msg)
}

func (s *Sender) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

func needsRefresh(now time.Time, cred mailapi.Credential) bool {
	return !cred.Expiry.IsZero() && cred.Expiry.Sub(now) <= oauthRefreshMargin
}

type xoauth2Auth struct {
	username    string
	accessToken string
}

func (a xoauth2Auth) Start(*smtp.ServerInfo) (string, []byte, error) {
	if a.username == "" || a.accessToken == "" {
		return "", nil, errors.New("missing xoauth2 credential")
	}
	resp := "user=" + a.username + "\x01auth=Bearer " + a.accessToken + "\x01\x01"
	return "XOAUTH2", []byte(resp), nil
}

func (a xoauth2Auth) Next(_ []byte, more bool) ([]byte, error) {
	if more {
		return nil, errors.New("xoauth2 authentication failed")
	}
	return nil, nil
}

func sendSMTPStartTLS(addr string, auth smtp.Auth, from string, rcpts []string, msg []byte) error {
	c, err := smtp.Dial(addr)
	if err != nil {
		return err
	}
	defer c.Close() //nolint:errcheck
	host := addr
	if i := strings.LastIndexByte(addr, ':'); i >= 0 {
		host = addr[:i]
	}
	if err := c.StartTLS(&tls.Config{ServerName: host, MinVersion: tls.VersionTLS12}); err != nil {
		return err
	}
	if err := c.Auth(auth); err != nil {
		return err
	}
	if err := c.Mail(from); err != nil {
		return err
	}
	for _, rcpt := range rcpts {
		if err := c.Rcpt(rcpt); err != nil {
			return err
		}
	}
	w, err := c.Data()
	if err != nil {
		return err
	}
	if _, err := w.Write(msg); err != nil {
		_ = w.Close()
		return err
	}
	if err := w.Close(); err != nil {
		return err
	}
	return c.Quit()
}

func (s *Sender) build(m mailapi.OutgoingMail) ([]byte, error) {
	var buf bytes.Buffer
	header(&buf, "From", formatAddr(m.From))
	header(&buf, "To", formatList(m.To))
	if len(m.CC) > 0 {
		header(&buf, "Cc", formatList(m.CC))
	}
	// Strip CR/LF from the raw Subject before Q-encoding (NR0011 S2). QEncoding already
	// encodes control bytes, but sanitizing first keeps the input clean regardless of the
	// encoder's behaviour and prevents the bytes from ever reaching the header line.
	header(&buf, "Subject", mime.QEncoding.Encode("utf-8", sanitizeHeaderValue(m.Subject)))
	buf.WriteString("MIME-Version: 1.0\r\n")

	contentType := "text/plain"
	if m.Body.Format == "html" {
		contentType = "text/html"
	}

	if len(m.Attachments) == 0 {
		fmt.Fprintf(&buf, "Content-Type: %s; charset=utf-8\r\n", contentType)
		buf.WriteString("Content-Transfer-Encoding: base64\r\n\r\n")
		writeBase64(&buf, []byte(m.Body.Content))
		return buf.Bytes(), nil
	}

	mw := multipart.NewWriter(io.Discard) // only used for a stable boundary
	boundary := mw.Boundary()
	fmt.Fprintf(&buf, "Content-Type: multipart/mixed; boundary=%q\r\n\r\n", boundary)

	// body part
	fmt.Fprintf(&buf, "--%s\r\n", boundary)
	fmt.Fprintf(&buf, "Content-Type: %s; charset=utf-8\r\n", contentType)
	buf.WriteString("Content-Transfer-Encoding: base64\r\n\r\n")
	writeBase64(&buf, []byte(m.Body.Content))
	buf.WriteString("\r\n")

	// attachment parts
	for _, a := range m.Attachments {
		var data []byte
		if s.Blob != nil && a.StorageRef != "" {
			rc, err := s.Blob.Open(a.StorageRef)
			if err == nil {
				data, _ = io.ReadAll(rc)
				rc.Close()
			}
		}
		ct := sanitizeHeaderValue(a.ContentType)
		if ct == "" {
			ct = "application/octet-stream"
		}
		fmt.Fprintf(&buf, "--%s\r\n", boundary)
		fmt.Fprintf(&buf, "Content-Type: %s\r\n", ct)
		fmt.Fprintf(&buf, "Content-Disposition: attachment; filename=%q\r\n",
			textproto.TrimString(a.Filename))
		buf.WriteString("Content-Transfer-Encoding: base64\r\n\r\n")
		writeBase64(&buf, data)
		buf.WriteString("\r\n")
	}
	fmt.Fprintf(&buf, "--%s--\r\n", boundary)
	return buf.Bytes(), nil
}

func header(buf *bytes.Buffer, k, v string) {
	fmt.Fprintf(buf, "%s: %s\r\n", k, sanitizeHeaderValue(v))
}

// sanitizeHeaderValue strips CR/LF (and other control chars) from a header value to
// block header/body injection (NR0011 S2). mime.QEncoding.Encode passes pure-ASCII
// Subjects through unencoded, so a Subject like "x\r\nBcc: v@x" would otherwise inject
// arbitrary headers. NUL and bare control bytes are dropped defensively.
func sanitizeHeaderValue(v string) string {
	if !strings.ContainsAny(v, "\r\n\x00") {
		return v
	}
	out := make([]rune, 0, len(v))
	for _, c := range v {
		if c == '\r' || c == '\n' || c == '\x00' {
			continue
		}
		out = append(out, c)
	}
	return string(out)
}

func formatAddr(a mailapi.Address) string {
	if a.Name == "" {
		return a.Address
	}
	return (&mail.Address{Name: a.Name, Address: a.Address}).String()
}

func formatList(as []mailapi.Address) string {
	parts := make([]string, 0, len(as))
	for _, a := range as {
		parts = append(parts, formatAddr(a))
	}
	return strings.Join(parts, ", ")
}

// writeBase64 emits standard base64 wrapped at 76 columns (RFC 2045).
func writeBase64(buf *bytes.Buffer, data []byte) {
	enc := base64.StdEncoding.EncodeToString(data)
	for len(enc) > 76 {
		buf.WriteString(enc[:76])
		buf.WriteString("\r\n")
		enc = enc[76:]
	}
	buf.WriteString(enc)
	buf.WriteString("\r\n")
}
