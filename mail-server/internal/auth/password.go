package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

// argon2id parameters — L0011 §1.
const (
	argonMem     = 64 * 1024 // KiB (64 MiB)
	argonTime    = 3
	argonThreads = 1
	argonKeyLen  = 32
	argonSaltLen = 16
)

// DummyHash is a fixed argon2id hash used to equalize timing for unknown accounts
// (L0011 dummy_verify_on_miss). Generated lazily once at startup.
var DummyHash = mustHash("__mailanchor_dummy__")

// HashPassword returns a self-describing argon2id encoded hash
// ($argon2id$v=19$m=...,t=...,p=...$salt$hash) so parameters travel with the hash
// and can be upgraded later (L0011 §5 gradual upgrade).
func HashPassword(plain string) (string, error) {
	salt := make([]byte, argonSaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	sum := argon2.IDKey([]byte(plain), salt, argonTime, argonMem, argonThreads, argonKeyLen)
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, argonMem, argonTime, argonThreads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(sum),
	), nil
}

// VerifyPassword performs a constant-time comparison against a self-describing hash.
func VerifyPassword(plain, encoded string) bool {
	p, salt, want, err := decodeHash(encoded)
	if err != nil {
		return false
	}
	got := argon2.IDKey([]byte(plain), salt, p.time, p.mem, p.threads, uint32(len(want)))
	return subtle.ConstantTimeCompare(got, want) == 1
}

type argonParams struct {
	mem, time uint32
	threads   uint8
}

func decodeHash(encoded string) (argonParams, []byte, []byte, error) {
	parts := strings.Split(encoded, "$")
	// ["", "argon2id", "v=19", "m=..,t=..,p=..", salt, hash]
	if len(parts) != 6 || parts[1] != "argon2id" {
		return argonParams{}, nil, nil, errors.New("invalid argon2id hash format")
	}
	var p argonParams
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &p.mem, &p.time, &p.threads); err != nil {
		return argonParams{}, nil, nil, err
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return argonParams{}, nil, nil, err
	}
	hash, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return argonParams{}, nil, nil, err
	}
	return p, salt, hash, nil
}

func mustHash(plain string) string {
	h, err := HashPassword(plain)
	if err != nil {
		panic("auth: dummy hash init failed: " + err.Error())
	}
	return h
}
