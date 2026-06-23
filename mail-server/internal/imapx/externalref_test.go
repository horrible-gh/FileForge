package imapx

import "testing"

// NR0011 B4: the dedup key must be the stable Message-ID (not the UID), so a UIDVALIDITY
// reset that re-assigns UIDs does not create duplicate rows / reset is_read.
func TestExternalRefPrefersMessageID(t *testing.T) {
	// same message, different UIDs (post-UIDVALIDITY-reset) -> same external_ref
	a := externalRef(10, "<abc@mail.example>")
	b := externalRef(99, "<abc@mail.example>")
	if a != b {
		t.Fatalf("message-id must yield a stable ref across UIDs: %q vs %q", a, b)
	}
	if a != "mid:abc@mail.example" {
		t.Fatalf("unexpected ref: %q", a)
	}

	// angle brackets + surrounding whitespace are normalized away
	if got := externalRef(1, "  <x@y>  "); got != "mid:x@y" {
		t.Fatalf("normalization failed: %q", got)
	}

	// no Message-ID -> fall back to the UID
	if got := externalRef(42, ""); got != "42" {
		t.Fatalf("uid fallback failed: %q", got)
	}
	if got := externalRef(42, "   "); got != "42" {
		t.Fatalf("blank message-id should fall back to uid: %q", got)
	}
}

// mapMessage stamps LabelsPartial (INBOX-only fetch) and the Message-ID-based ref.
func TestMapMessagePartialLabelsAndStableRef(t *testing.T) {
	raw := "From: a@x.com\r\nTo: u@x.com\r\nSubject: hi\r\nMessage-Id: <m1@x.com>\r\n\r\nbody"
	ch, err := mapMessage(7, []byte(raw), true)
	if err != nil {
		t.Fatalf("mapMessage: %v", err)
	}
	if !ch.LabelsPartial {
		t.Fatal("IMAP inbox fetch must mark labels partial (B3)")
	}
	if ch.ExternalID != "mid:m1@x.com" {
		t.Fatalf("external ref should use Message-ID: %q", ch.ExternalID)
	}
}
