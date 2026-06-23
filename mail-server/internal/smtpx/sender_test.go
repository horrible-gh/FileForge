package smtpx

import (
	"bytes"
	"io"
	"strings"
	"testing"

	"mailanchor/serverd/internal/mailapi"
)

// fakeBlob serves fixed bytes for any ref (build() only calls Open).
type fakeBlob struct{ data []byte }

func (f fakeBlob) Put(io.Reader) (string, int64, error) { return "", 0, nil }
func (f fakeBlob) Open(string) (io.ReadCloser, error) {
	return io.NopCloser(bytes.NewReader(f.data)), nil
}
func (f fakeBlob) Delete(string) error { return nil }

// headerLines returns the message header block (up to the first blank line).
func headerBlock(msg []byte) string {
	if i := bytes.Index(msg, []byte("\r\n\r\n")); i >= 0 {
		return string(msg[:i])
	}
	return string(msg)
}

// NR0011 S2: a Subject carrying CRLF must not inject extra headers/body. ASCII Subjects
// pass through mime.QEncoding unencoded, so without sanitization the CRLF would survive.
func TestBuildSubjectCRLFInjectionBlocked(t *testing.T) {
	s := &Sender{}
	msg, err := s.build(mailapi.OutgoingMail{
		From:    mailapi.Address{Address: "me@x.com"},
		To:      []mailapi.Address{{Address: "you@x.com"}},
		Subject: "Hello\r\nBcc: victim@evil.com\r\n\r\ninjected body",
		Body:    mailapi.Body{Format: "text", Content: "ok"},
	})
	if err != nil {
		t.Fatalf("build: %v", err)
	}
	// No injected header line may appear: the CRLF must not split the Subject into a new
	// "Bcc:" header (the bytes are stripped before/after Q-encoding).
	for _, line := range strings.Split(headerBlock(msg), "\r\n") {
		if strings.HasPrefix(strings.ToLower(line), "bcc:") {
			t.Fatalf("CRLF injection produced a Bcc header line: %q", line)
		}
	}
}

// NR0011 S2: attachment Content-Type is client-controlled and was written with %s — CRLF
// in it could inject headers. It must be sanitized.
func TestBuildAttachmentContentTypeCRLFBlocked(t *testing.T) {
	s := &Sender{Blob: fakeBlob{data: []byte("PDF")}}
	msg, err := s.build(mailapi.OutgoingMail{
		From:    mailapi.Address{Address: "me@x.com"},
		To:      []mailapi.Address{{Address: "you@x.com"}},
		Subject: "x",
		Body:    mailapi.Body{Format: "text", Content: "ok"},
		Attachments: []mailapi.OutgoingAttachment{{
			Filename: "a.pdf", ContentType: "application/pdf\r\nX-Injected: 1", StorageRef: "ref1",
		}},
	})
	if err != nil {
		t.Fatalf("build: %v", err)
	}
	// the injected text must not become its own header line (CRLF stripped); folding it
	// into the Content-Type value is harmless.
	if strings.Contains(string(msg), "\r\nX-Injected:") {
		t.Fatalf("attachment Content-Type CRLF injection survived as a header line:\n%s", msg)
	}
	if !strings.Contains(string(msg), "multipart/mixed") {
		t.Fatal("expected multipart/mixed for an attachment message")
	}
}

// NR0011 T1 (smtpx MIME builder had zero tests): BCC must never appear as a header (it is
// an envelope-only recipient); the regression risk was a leak into the message headers.
func TestBuildBCCNotInHeaders(t *testing.T) {
	s := &Sender{}
	msg, err := s.build(mailapi.OutgoingMail{
		From:    mailapi.Address{Address: "me@x.com"},
		To:      []mailapi.Address{{Address: "you@x.com"}},
		CC:      []mailapi.Address{{Address: "cc@x.com"}},
		BCC:     []mailapi.Address{{Address: "secret@x.com"}},
		Subject: "hi",
		Body:    mailapi.Body{Format: "text", Content: "ok"},
	})
	if err != nil {
		t.Fatalf("build: %v", err)
	}
	hdr := headerBlock(msg)
	if strings.Contains(hdr, "secret@x.com") || strings.Contains(strings.ToLower(hdr), "bcc:") {
		t.Fatalf("BCC leaked into headers:\n%s", hdr)
	}
	if !strings.Contains(hdr, "Cc: cc@x.com") {
		t.Fatalf("Cc header missing:\n%s", hdr)
	}
}
