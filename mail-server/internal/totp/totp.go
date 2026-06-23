// Package totp implements RFC 6238 time-based one-time passwords and one-time recovery
// codes for the R0001 stage-4 2FA flow. It is dependency-free (crypto/hmac + crypto/sha1
// + encoding/base32) rather than pulling pyotp's Go analogue, keeping the cgo-free
// single-binary build the sidecar already relies on. The parameters (SHA-1, 30s step,
// 6 digits, base32 secret) match the MailAnchor auth2fa package so an authenticator app
// enrolled against either backend produces identical codes.
package totp

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1" //nolint:gosec // RFC 6238 / RFC 4226 mandate HMAC-SHA1 for TOTP interop
	"crypto/subtle"
	"encoding/base32"
	"encoding/binary"
	"fmt"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const (
	// Period is the TOTP time step (RFC 6238 default 30s).
	Period = 30 * time.Second
	// Digits is the code length (RFC 6238 / authenticator-app default 6).
	Digits = 6
	// secretBytes is the entropy of a freshly generated secret (160-bit, RFC 4226 §4 min).
	secretBytes = 20
)

// b32 is unpadded uppercase base32, the form pyotp.random_base32 and authenticator apps use.
var b32 = base32.StdEncoding.WithPadding(base32.NoPadding)

// GenerateSecret returns a new random base32 TOTP secret (uppercase, unpadded).
func GenerateSecret() (string, error) {
	buf := make([]byte, secretBytes)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return b32.EncodeToString(buf), nil
}

// Code returns the 6-digit TOTP for secret at time t.
func Code(secret string, t time.Time) (string, error) {
	return codeForCounter(secret, counterAt(t), Digits)
}

// Verify reports whether code matches secret at time t within ±skew time steps (so a code
// generated up to skew*30s early/late, e.g. on a slightly skewed phone clock, still passes).
// Comparison is constant-time. A code of the wrong length or an undecodable secret is false.
func Verify(secret, code string, t time.Time, skew int) bool {
	code = strings.TrimSpace(code)
	if len(code) != Digits {
		return false
	}
	if skew < 0 {
		skew = 0
	}
	base := counterAt(t)
	for d := -skew; d <= skew; d++ {
		c := base
		if d < 0 {
			c -= uint64(-d)
		} else {
			c += uint64(d)
		}
		want, err := codeForCounter(secret, c, Digits)
		if err != nil {
			return false
		}
		if subtle.ConstantTimeCompare([]byte(want), []byte(code)) == 1 {
			return true
		}
	}
	return false
}

// ProvisioningURI builds the otpauth:// URI an authenticator app scans (the QR payload).
// The server returns this string and lets the client render the QR, avoiding a server-side
// image-encoding dependency while staying interoperable with the MailAnchor enrollment.
func ProvisioningURI(secret, account, issuer string) string {
	label := url.PathEscape(issuer + ":" + account)
	v := url.Values{}
	v.Set("secret", secret)
	v.Set("issuer", issuer)
	v.Set("algorithm", "SHA1")
	v.Set("digits", strconv.Itoa(Digits))
	v.Set("period", strconv.Itoa(int(Period.Seconds())))
	return "otpauth://totp/" + label + "?" + v.Encode()
}

// counterAt is the RFC 6238 time-step counter T = floor(unixSeconds / period).
func counterAt(t time.Time) uint64 {
	return uint64(t.Unix()) / uint64(Period.Seconds())
}

// codeForCounter is the RFC 4226 HOTP truncation over an 8-byte big-endian counter.
func codeForCounter(secret string, counter uint64, digits int) (string, error) {
	key, err := decodeSecret(secret)
	if err != nil {
		return "", err
	}
	var msg [8]byte
	binary.BigEndian.PutUint64(msg[:], counter)
	mac := hmac.New(sha1.New, key)
	mac.Write(msg[:])
	sum := mac.Sum(nil)
	offset := sum[len(sum)-1] & 0x0f
	bin := (uint32(sum[offset])&0x7f)<<24 |
		uint32(sum[offset+1])<<16 |
		uint32(sum[offset+2])<<8 |
		uint32(sum[offset+3])
	mod := uint32(1)
	for i := 0; i < digits; i++ {
		mod *= 10
	}
	return fmt.Sprintf("%0*d", digits, bin%mod), nil
}

// decodeSecret accepts a base32 secret with or without padding/whitespace/case, matching
// the lenience of authenticator apps and pyotp.
func decodeSecret(secret string) ([]byte, error) {
	s := strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(secret), " ", ""))
	if key, err := b32.DecodeString(s); err == nil {
		return key, nil
	}
	return base32.StdEncoding.DecodeString(s)
}
