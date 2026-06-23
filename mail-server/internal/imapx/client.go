package imapx

import (
	"bufio"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net"
	"regexp"
	"strconv"
	"strings"
)

// client is a minimal line-oriented IMAP4rev1 client over an established connection.
// It implements only the verbs the incremental fetch needs (AUTHENTICATE XOAUTH2,
// SELECT, UID SEARCH, UID FETCH) and a literal-aware response reader.
type client struct {
	conn net.Conn
	r    *bufio.Reader
	w    *bufio.Writer
	tag  int
}

func newClient(conn net.Conn) *client {
	c := &client{conn: conn, r: bufio.NewReader(conn), w: bufio.NewWriter(conn)}
	// Consume the server greeting ("* OK ...") so the first command reads its own reply.
	_, _ = c.r.ReadString('\n')
	return c
}

func (c *client) close() {
	// Best-effort LOGOUT then close.
	tag := c.nextTag()
	fmt.Fprintf(c.w, "%s LOGOUT\r\n", tag)
	_ = c.w.Flush()
	_ = c.conn.Close()
}

func (c *client) nextTag() string {
	c.tag++
	return "a" + strconv.Itoa(c.tag)
}

// readLine reads one raw protocol line (without the trailing CRLF).
func (c *client) readLine() (string, error) {
	line, err := c.r.ReadString('\n')
	if err != nil {
		return "", err
	}
	return strings.TrimRight(line, "\r\n"), nil
}

var literalSuffix = regexp.MustCompile(`\{(\d+)\}$`)

// readResponse reads untagged lines until the tagged completion for tag, invoking
// onUntagged for each untagged ("* ...") line. Literals are transparently read and the
// literal bytes are passed alongside the line. Returns an error on NO/BAD completion.
func (c *client) readResponse(tag string, onUntagged func(line string, literal []byte) error) error {
	for {
		line, err := c.readLine()
		if err != nil {
			return err
		}
		var literal []byte
		if m := literalSuffix.FindStringSubmatch(line); m != nil {
			n, _ := strconv.Atoi(m[1])
			literal = make([]byte, n)
			if _, err := io.ReadFull(c.r, literal); err != nil {
				return err
			}
			// The remainder of the response (after the literal) continues on following
			// lines; readLine on the next iteration picks it up. For our FETCH the tail
			// is just ")"—consume it here so it is not mistaken for a new response.
			tail, err := c.readLine()
			if err != nil {
				return err
			}
			line = line + tail
		}

		switch {
		case strings.HasPrefix(line, "* "):
			if onUntagged != nil {
				if err := onUntagged(strings.TrimPrefix(line, "* "), literal); err != nil {
					return err
				}
			}
		case strings.HasPrefix(line, "+ "):
			// Unexpected continuation request (e.g. SASL error). Abort by sending an
			// empty response and reporting failure.
			fmt.Fprint(c.w, "\r\n")
			_ = c.w.Flush()
			return fmt.Errorf("imapx: unexpected continuation: %s", line)
		case strings.HasPrefix(line, tag+" "):
			rest := strings.TrimPrefix(line, tag+" ")
			if strings.HasPrefix(rest, "OK") {
				return nil
			}
			return fmt.Errorf("imapx: command failed: %s", rest)
		}
	}
}

// authXOAuth2 authenticates with SASL XOAUTH2 (RFC 7628 style initial response).
func (c *client) authXOAuth2(email, accessToken string) error {
	tag := c.nextTag()
	sasl := "user=" + email + "\x01auth=Bearer " + accessToken + "\x01\x01"
	enc := base64.StdEncoding.EncodeToString([]byte(sasl))
	fmt.Fprintf(c.w, "%s AUTHENTICATE XOAUTH2 %s\r\n", tag, enc)
	if err := c.w.Flush(); err != nil {
		return err
	}
	if err := c.readResponse(tag, nil); err != nil {
		return fmt.Errorf("imapx: XOAUTH2 auth failed: %w", err)
	}
	return nil
}

var uidValidityRe = regexp.MustCompile(`UIDVALIDITY (\d+)`)

// selectInbox issues SELECT INBOX and returns the mailbox UIDVALIDITY.
func (c *client) selectInbox() (uint32, error) {
	tag := c.nextTag()
	fmt.Fprintf(c.w, "%s SELECT INBOX\r\n", tag)
	if err := c.w.Flush(); err != nil {
		return 0, err
	}
	var uidValidity uint32
	err := c.readResponse(tag, func(line string, _ []byte) error {
		if m := uidValidityRe.FindStringSubmatch(line); m != nil {
			v, _ := strconv.ParseUint(m[1], 10, 32)
			uidValidity = uint32(v)
		}
		return nil
	})
	if err != nil {
		return 0, err
	}
	return uidValidity, nil
}

// searchUIDsAbove returns inbox UIDs strictly greater than lastUID.
func (c *client) searchUIDsAbove(lastUID uint32) ([]uint32, error) {
	tag := c.nextTag()
	low := lastUID + 1
	fmt.Fprintf(c.w, "%s UID SEARCH UID %d:*\r\n", tag, low)
	if err := c.w.Flush(); err != nil {
		return nil, err
	}
	var uids []uint32
	err := c.readResponse(tag, func(line string, _ []byte) error {
		fields := strings.Fields(line)
		if len(fields) == 0 || !strings.EqualFold(fields[0], "SEARCH") {
			return nil
		}
		for _, f := range fields[1:] {
			if v, perr := strconv.ParseUint(f, 10, 32); perr == nil {
				// "UID m:*" matches the highest UID even when m > highest, so the server
				// may echo lastUID itself; filter to strictly-greater.
				if uint32(v) > lastUID {
					uids = append(uids, uint32(v))
				}
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return uids, nil
}

var uidRe = regexp.MustCompile(`UID (\d+)`)
var flagsRe = regexp.MustCompile(`FLAGS \(([^)]*)\)`)

// fetchMessage fetches one message's full body + flags by UID. Returns the raw RFC 5322
// bytes and whether the \Seen flag is set.
func (c *client) fetchMessage(uid uint32) (raw []byte, seen bool, err error) {
	tag := c.nextTag()
	fmt.Fprintf(c.w, "%s UID FETCH %d (UID FLAGS BODY.PEEK[])\r\n", tag, uid)
	if err := c.w.Flush(); err != nil {
		return nil, false, err
	}
	rerr := c.readResponse(tag, func(line string, literal []byte) error {
		if !strings.Contains(line, "FETCH") {
			return nil
		}
		if literal != nil {
			raw = literal
		}
		if m := flagsRe.FindStringSubmatch(line); m != nil {
			seen = strings.Contains(m[1], `\Seen`)
		}
		return nil
	})
	if rerr != nil {
		return nil, false, rerr
	}
	if raw == nil {
		return nil, false, errors.New("imapx: FETCH returned no body")
	}
	return raw, seen, nil
}
