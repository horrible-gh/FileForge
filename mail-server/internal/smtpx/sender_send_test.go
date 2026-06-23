package smtpx

import (
	"bufio"
	"bytes"
	"net"
	"strings"
	"testing"
	"time"

	"mailanchor/serverd/internal/mailapi"
)

// capturedSMTP records what a minimal in-process SMTP sink received: the envelope
// (MAIL FROM / RCPT TO) and the DATA payload.
type capturedSMTP struct {
	mailFrom string
	rcpts    []string
	data     string
	done     chan struct{}
}

func angleAddr(line string) string {
	if i := strings.IndexByte(line, '<'); i >= 0 {
		if j := strings.IndexByte(line[i:], '>'); j > 0 {
			return line[i+1 : i+j]
		}
	}
	return strings.TrimSpace(line)
}

// startSMTPSink runs a loopback SMTP server that speaks just enough of RFC 5321 to walk
// stdlib net/smtp through EHLO -> MAIL -> RCPT -> DATA -> QUIT without advertising
// STARTTLS or AUTH (so the unauthenticated Sender path is exercised end-to-end over a
// real TCP socket). It returns the listen addr and the capture handle.
func startSMTPSink(t *testing.T) (string, *capturedSMTP) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	cap := &capturedSMTP{done: make(chan struct{})}
	go func() {
		defer close(cap.done)
		defer ln.Close()
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		br := bufio.NewReader(conn)
		write := func(s string) { _, _ = conn.Write([]byte(s)) }

		write("220 sink ESMTP ready\r\n")
		var data bytes.Buffer
		inData := false
		for {
			line, err := br.ReadString('\n')
			if err != nil {
				return
			}
			if inData {
				if line == ".\r\n" {
					inData = false
					cap.data = data.String()
					write("250 2.0.0 OK queued\r\n")
					continue
				}
				data.WriteString(line)
				continue
			}
			cmd := strings.ToUpper(strings.TrimSpace(line))
			switch {
			case strings.HasPrefix(cmd, "EHLO"), strings.HasPrefix(cmd, "HELO"):
				// Multiline 250 that advertises neither STARTTLS nor AUTH.
				write("250-sink greets you\r\n250 OK\r\n")
			case strings.HasPrefix(cmd, "MAIL FROM"):
				cap.mailFrom = angleAddr(line)
				write("250 2.1.0 OK\r\n")
			case strings.HasPrefix(cmd, "RCPT TO"):
				cap.rcpts = append(cap.rcpts, angleAddr(line))
				write("250 2.1.5 OK\r\n")
			case strings.HasPrefix(cmd, "DATA"):
				inData = true
				write("354 End data with <CR><LF>.<CR><LF>\r\n")
			case strings.HasPrefix(cmd, "QUIT"):
				write("221 2.0.0 Bye\r\n")
				return
			default:
				write("250 OK\r\n")
			}
		}
	}()
	return ln.Addr().String(), cap
}

// TestSendDeliversOverLoopbackSMTP is the SMTP-adapter live transport smoke
// (mailanchor.ui.0003 T3): it drives Sender.Send through stdlib net/smtp over a real
// loopback socket — the existing tests only cover build(). It asserts the SMTP envelope
// carries every recipient (To+Cc+Bcc), while the delivered DATA keeps Bcc out of the
// headers and contains the Subject and body. This is a transport-level smoke, NOT a
// real-account/provider smoke (which still needs live credentials — see README).
func TestSendDeliversOverLoopbackSMTP(t *testing.T) {
	addr, cap := startSMTPSink(t)

	s := &Sender{Addr: addr, Auth: nil, Blob: fakeBlob{data: []byte("PDFBYTES")}}
	err := s.Send(mailapi.ExternalAccount{}, mailapi.OutgoingMail{
		From:    mailapi.Address{Name: "Me", Address: "me@x.com"},
		To:      []mailapi.Address{{Address: "you@x.com"}},
		CC:      []mailapi.Address{{Address: "cc@x.com"}},
		BCC:     []mailapi.Address{{Address: "secret@x.com"}},
		Subject: "Live SMTP smoke",
		Body:    mailapi.Body{Format: "text", Content: "hello over the wire"},
		Attachments: []mailapi.OutgoingAttachment{{
			Filename: "a.pdf", ContentType: "application/pdf", StorageRef: "ref1",
		}},
	})
	if err != nil {
		t.Fatalf("Send over loopback SMTP: %v", err)
	}

	select {
	case <-cap.done:
	case <-time.After(5 * time.Second):
		t.Fatal("sink did not finish the SMTP dialog")
	}

	if cap.mailFrom != "me@x.com" {
		t.Fatalf("MAIL FROM = %q, want me@x.com", cap.mailFrom)
	}
	// Envelope must include the Bcc recipient even though it is absent from the headers.
	want := map[string]bool{"you@x.com": false, "cc@x.com": false, "secret@x.com": false}
	for _, r := range cap.rcpts {
		if _, ok := want[r]; ok {
			want[r] = true
		}
	}
	for addr, seen := range want {
		if !seen {
			t.Errorf("envelope missing recipient %q (got %v)", addr, cap.rcpts)
		}
	}

	hdr := headerBlock([]byte(cap.data))
	if strings.Contains(strings.ToLower(hdr), "bcc:") || strings.Contains(hdr, "secret@x.com") {
		t.Errorf("Bcc leaked into delivered headers:\n%s", hdr)
	}
	if !strings.Contains(cap.data, "Live SMTP smoke") {
		t.Error("delivered message missing Subject")
	}
	// Body is base64 — decode-independent check: the multipart attachment boundary made it
	// onto the wire, proving the full build()+transport path ran.
	if !strings.Contains(cap.data, "multipart/mixed") {
		t.Error("delivered message missing multipart/mixed body")
	}
}
