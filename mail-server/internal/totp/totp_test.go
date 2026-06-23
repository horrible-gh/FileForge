package totp

import (
	"encoding/base32"
	"net/url"
	"strings"
	"testing"
	"time"
)

// rfcSecret is the RFC 6238 Appendix B SHA-1 seed ("12345678901234567890") as base32.
func rfcSecret(t *testing.T) string {
	t.Helper()
	return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString([]byte("12345678901234567890"))
}

// TestCodeMatchesRFC6238 checks our HOTP truncation against the published RFC 6238 SHA-1
// test vectors (8-digit codes; we compare the low 6 digits our Code emits).
func TestCodeMatchesRFC6238(t *testing.T) {
	secret := rfcSecret(t)
	cases := []struct {
		unix int64
		want string // last 6 digits of the RFC 8-digit vector
	}{
		{59, "287082"},          // RFC vector 94287082
		{1111111109, "081804"},  // 07081804
		{1111111111, "050471"},  // 14050471
		{1234567890, "005924"},  // 89005924
		{2000000000, "279037"},  // 69279037
		{20000000000, "353130"}, // 65353130
	}
	for _, c := range cases {
		got, err := Code(secret, time.Unix(c.unix, 0).UTC())
		if err != nil {
			t.Fatalf("unix=%d: %v", c.unix, err)
		}
		if got != c.want {
			t.Errorf("unix=%d: code = %q, want %q", c.unix, got, c.want)
		}
	}
}

func TestVerifyAcceptsCurrentAndSkew(t *testing.T) {
	secret, err := GenerateSecret()
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1700000000, 0).UTC()
	code, err := Code(secret, now)
	if err != nil {
		t.Fatal(err)
	}
	if !Verify(secret, code, now, 1) {
		t.Fatal("current code must verify")
	}
	// A code from one step ago must still pass with skew=1 (clock drift tolerance)...
	if !Verify(secret, code, now.Add(Period), 1) {
		t.Error("previous-step code should verify within skew=1")
	}
	// ...but not with skew=0 (no tolerance).
	if Verify(secret, code, now.Add(Period), 0) {
		t.Error("previous-step code must NOT verify with skew=0")
	}
	// Two steps away is outside the ±1 window.
	if Verify(secret, code, now.Add(2*Period), 1) {
		t.Error("two-steps-away code must not verify within skew=1")
	}
}

func TestVerifyRejectsMalformed(t *testing.T) {
	secret, _ := GenerateSecret()
	now := time.Now()
	if Verify(secret, "12345", now, 1) { // wrong length
		t.Error("short code must be rejected")
	}
	if Verify(secret, "", now, 1) {
		t.Error("empty code must be rejected")
	}
	if Verify("!!!not-base32!!!", "123456", now, 1) {
		t.Error("undecodable secret must be rejected, not panic")
	}
}

func TestProvisioningURI(t *testing.T) {
	secret := "JBSWY3DPEHPK3PXP"
	uri := ProvisioningURI(secret, "alice@example.com", "MailAnchor")
	if !strings.HasPrefix(uri, "otpauth://totp/") {
		t.Fatalf("bad scheme: %s", uri)
	}
	u, err := url.Parse(uri)
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	if q.Get("secret") != secret {
		t.Errorf("secret = %q", q.Get("secret"))
	}
	if q.Get("issuer") != "MailAnchor" {
		t.Errorf("issuer = %q", q.Get("issuer"))
	}
	if q.Get("digits") != "6" || q.Get("period") != "30" || q.Get("algorithm") != "SHA1" {
		t.Errorf("unexpected params: %v", q)
	}
}

func TestGenerateRecoveryCodes(t *testing.T) {
	codes, err := GenerateRecoveryCodes(8, 8)
	if err != nil {
		t.Fatal(err)
	}
	if len(codes) != 8 {
		t.Fatalf("count = %d, want 8", len(codes))
	}
	seen := map[string]bool{}
	for _, c := range codes {
		if len(c) != 8 {
			t.Errorf("len(%q) = %d, want 8", c, len(c))
		}
		if seen[c] {
			t.Errorf("duplicate recovery code %q", c)
		}
		seen[c] = true
		if strings.ContainsAny(c, "01OI") {
			t.Errorf("recovery code %q contains an ambiguous character", c)
		}
	}
}
