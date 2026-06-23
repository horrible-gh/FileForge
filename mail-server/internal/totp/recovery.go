package totp

import "crypto/rand"

// recoveryAlphabet is uppercase letters + digits with the visually ambiguous 0/O/1/I
// removed, matching the MailAnchor auth2fa recovery-code charset.
const recoveryAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // len 32 -> no modulo bias from a byte

// GenerateRecoveryCodes returns count single-use recovery codes of the given length, each
// drawn uniformly from recoveryAlphabet (crypto/rand). Used as a TOTP backup when the
// authenticator device is lost.
func GenerateRecoveryCodes(count, length int) ([]string, error) {
	codes := make([]string, 0, count)
	for i := 0; i < count; i++ {
		buf := make([]byte, length)
		if _, err := rand.Read(buf); err != nil {
			return nil, err
		}
		out := make([]byte, length)
		for j, b := range buf {
			out[j] = recoveryAlphabet[int(b)%len(recoveryAlphabet)]
		}
		codes = append(codes, string(out))
	}
	return codes, nil
}
