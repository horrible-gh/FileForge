package mailapi

import (
	"bytes"
	"testing"
	"time"

	"mailanchor/serverd/internal/sharedstore"
)

// R0001 stage 5: the encrypted secret store round-trips a credential, but never holds the
// plaintext token in its backing map (at-rest encryption, DB0008 §2.3).
func TestEncryptedSecretStoreRoundTripAndAtRest(t *testing.T) {
	s, err := NewEncryptedSecretStore([]byte("a-test-encryption-key"))
	if err != nil {
		t.Fatalf("new: %v", err)
	}
	cred := Credential{AccessToken: "ya29.SECRET-ACCESS", RefreshToken: "1//SECRET-REFRESH", Expiry: time.Unix(1700000000, 0).UTC()}
	s.Put("gmail:user-1", cred)

	got, ok := s.Get("gmail:user-1")
	if !ok {
		t.Fatal("credential should be retrievable")
	}
	if got.AccessToken != cred.AccessToken || got.RefreshToken != cred.RefreshToken || !got.Expiry.Equal(cred.Expiry) {
		t.Fatalf("round-trip mismatch: %+v vs %+v", got, cred)
	}

	// The backing blob must not contain the plaintext tokens (it is ciphertext at rest).
	blob := s.m["gmail:user-1"]
	if bytes.Contains(blob, []byte("ya29.SECRET-ACCESS")) || bytes.Contains(blob, []byte("1//SECRET-REFRESH")) {
		t.Fatal("plaintext token found in stored blob — at-rest encryption broken")
	}

	s.Delete("gmail:user-1")
	if _, ok := s.Get("gmail:user-1"); ok {
		t.Fatal("credential should be gone after delete")
	}
}

func TestEncryptedSecretStoreRejectsEmptyKeyAndTamper(t *testing.T) {
	if _, err := NewEncryptedSecretStore(nil); err == nil {
		t.Fatal("empty key must be rejected")
	}
	s, _ := NewEncryptedSecretStore([]byte("k"))
	s.Put("ref", Credential{AccessToken: "tok"})
	// Tamper the stored ciphertext -> GCM auth fails -> Get reports not-found (no forged cred).
	s.m["ref"][len(s.m["ref"])-1] ^= 0xff
	if _, ok := s.Get("ref"); ok {
		t.Fatal("tampered blob must not open")
	}
	// Missing ref -> not found.
	if _, ok := s.Get("nope"); ok {
		t.Fatal("absent ref must be not-found")
	}
}

// The encrypted store satisfies the SecretStore port (drop-in for MemSecretStore).
func TestEncryptedSecretStoreImplementsPort(t *testing.T) {
	var _ SecretStore = (*EncryptedSecretStore)(nil)
}

// R0001 stage 5: the shared-store-backed OAuth state store preserves the single-use +
// binding semantics of MemStateStore, now over the cross-instance shared store.
func TestSharedStateStoreSingleUse(t *testing.T) {
	mem := sharedstore.NewMemStore()
	ss := NewSharedStateStore(mem)

	ss.Put("state-xyz", "user-9", "gmail")
	uid, provider, ok := ss.Take("state-xyz")
	if !ok || uid != "user-9" || provider != "gmail" {
		t.Fatalf("take = (%q,%q,%v), want (user-9,gmail,true)", uid, provider, ok)
	}
	// Single-use: a second Take of the same state must fail.
	if _, _, ok := ss.Take("state-xyz"); ok {
		t.Fatal("state must be consumed after first Take")
	}
	// Unknown state -> not found.
	if _, _, ok := ss.Take("never-issued"); ok {
		t.Fatal("unknown state must be not-found")
	}
}
