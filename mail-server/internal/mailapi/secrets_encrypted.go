package mailapi

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"io"
	"sync"
)

// EncryptedSecretStore is a SecretStore that keeps OAuth credentials encrypted at rest with
// AES-256-GCM (R0001 stage 5; DB0008 §2.3: "자격 원문은 비밀저장소"·암호화 저장). Unlike
// MemSecretStore it never holds a plaintext Credential in its backing map — values are sealed
// on Put and only opened transiently inside Get — so a heap dump, accidental log, or a future
// persistent backing store sees ciphertext (nonce‖ct‖tag), not live tokens. GCM also
// authenticates each blob, so a tampered/garbage value fails to open rather than yielding a
// forged credential.
//
// The key comes from config (MAILANCHOR_SECRET_ENCRYPTION_KEY); it is SHA-256-folded to a
// fixed 32-byte AES-256 key so any supplied key length is accepted. The store is selected by
// the router only when a key is configured; otherwise the in-memory dev default is kept
// (same "configure → use it, else degrade" gate as Redis/FileForge).
type EncryptedSecretStore struct {
	mu   sync.RWMutex
	m    map[string][]byte // ref -> nonce‖ciphertext‖tag
	aead cipher.AEAD
}

// NewEncryptedSecretStore builds the store from a raw key of any length (folded via SHA-256).
// An empty key is rejected so a misconfiguration fails loudly rather than silently disabling
// at-rest encryption.
func NewEncryptedSecretStore(key []byte) (*EncryptedSecretStore, error) {
	if len(key) == 0 {
		return nil, errors.New("encrypted secret store: empty key")
	}
	sum := sha256.Sum256(key)
	block, err := aes.NewCipher(sum[:])
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	return &EncryptedSecretStore{m: map[string][]byte{}, aead: aead}, nil
}

func (s *EncryptedSecretStore) Get(ref string) (Credential, bool) {
	s.mu.RLock()
	blob, ok := s.m[ref]
	s.mu.RUnlock()
	if !ok {
		return Credential{}, false
	}
	ns := s.aead.NonceSize()
	if len(blob) < ns {
		return Credential{}, false
	}
	plain, err := s.aead.Open(nil, blob[:ns], blob[ns:], nil)
	if err != nil {
		return Credential{}, false // tampered / wrong key
	}
	var cred Credential
	if err := json.Unmarshal(plain, &cred); err != nil {
		return Credential{}, false
	}
	return cred, true
}

// Put seals the credential under a fresh random nonce. The SecretStore contract is errorless;
// the only failure modes here are a JSON-marshal of a 3-field struct (cannot fail) or a
// system entropy failure (catastrophic) — in either case the ref is left unset rather than
// stored in the clear.
func (s *EncryptedSecretStore) Put(ref string, cred Credential) {
	plain, err := json.Marshal(cred)
	if err != nil {
		return
	}
	nonce := make([]byte, s.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return
	}
	blob := s.aead.Seal(nonce, nonce, plain, nil)
	s.mu.Lock()
	s.m[ref] = blob
	s.mu.Unlock()
}

func (s *EncryptedSecretStore) Delete(ref string) {
	s.mu.Lock()
	delete(s.m, ref)
	s.mu.Unlock()
}
