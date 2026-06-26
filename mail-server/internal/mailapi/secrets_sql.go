package mailapi

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"io"
	"time"
)

const (
	secretBlobPlain = "plain:"
	secretBlobGCM   = "gcm1:"
)

// SQLSecretStore persists OAuth credentials in the application DB so oauth_ref survives
// process restarts. When key is non-empty, blobs are AES-256-GCM encrypted; otherwise
// development deployments store JSON with an explicit plaintext prefix.
type SQLSecretStore struct {
	db   *sql.DB
	aead cipher.AEAD
}

func NewSQLSecretStore(db *sql.DB, key []byte) *SQLSecretStore {
	s := &SQLSecretStore{db: db}
	if len(key) > 0 {
		sum := sha256.Sum256(key)
		if block, err := aes.NewCipher(sum[:]); err == nil {
			if aead, err := cipher.NewGCM(block); err == nil {
				s.aead = aead
			}
		}
	}
	return s
}

func (s *SQLSecretStore) Get(ref string) (Credential, bool) {
	if s == nil || s.db == nil || ref == "" {
		return Credential{}, false
	}
	var blob []byte
	if err := s.db.QueryRow(`SELECT credential_blob FROM oauth_secret WHERE oauth_ref=?`, ref).Scan(&blob); err != nil {
		return Credential{}, false
	}
	plain, ok := s.open(blob)
	if !ok {
		return Credential{}, false
	}
	var cred Credential
	if err := json.Unmarshal(plain, &cred); err != nil {
		return Credential{}, false
	}
	return cred, true
}

func (s *SQLSecretStore) Put(ref string, cred Credential) {
	if s == nil || s.db == nil || ref == "" {
		return
	}
	blob, ok := s.seal(cred)
	if !ok {
		return
	}
	now := time.Now().UTC().Truncate(time.Second).Format(tsLayout)
	tx, err := s.db.Begin()
	if err != nil {
		return
	}
	defer tx.Rollback() //nolint:errcheck
	if _, err := tx.Exec(`DELETE FROM oauth_secret WHERE oauth_ref=?`, ref); err != nil {
		return
	}
	if _, err := tx.Exec(
		`INSERT INTO oauth_secret(oauth_ref,credential_blob,created_at,updated_at) VALUES(?,?,?,?)`,
		ref, blob, now, now); err != nil {
		return
	}
	_ = tx.Commit()
}

func (s *SQLSecretStore) Delete(ref string) {
	if s == nil || s.db == nil || ref == "" {
		return
	}
	_, _ = s.db.Exec(`DELETE FROM oauth_secret WHERE oauth_ref=?`, ref)
}

func (s *SQLSecretStore) seal(cred Credential) ([]byte, bool) {
	plain, err := json.Marshal(cred)
	if err != nil {
		return nil, false
	}
	if s.aead == nil {
		return append([]byte(secretBlobPlain), plain...), true
	}
	nonce := make([]byte, s.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, false
	}
	sealed := s.aead.Seal(nonce, nonce, plain, nil)
	return append([]byte(secretBlobGCM), sealed...), true
}

func (s *SQLSecretStore) open(blob []byte) ([]byte, bool) {
	switch {
	case hasPrefix(blob, secretBlobPlain):
		return blob[len(secretBlobPlain):], true
	case hasPrefix(blob, secretBlobGCM):
		if s.aead == nil {
			return nil, false
		}
		body := blob[len(secretBlobGCM):]
		ns := s.aead.NonceSize()
		if len(body) < ns {
			return nil, false
		}
		plain, err := s.aead.Open(nil, body[:ns], body[ns:], nil)
		return plain, err == nil
	default:
		return nil, false
	}
}

func hasPrefix(b []byte, prefix string) bool {
	p := []byte(prefix)
	if len(b) < len(p) {
		return false
	}
	for i := range p {
		if b[i] != p[i] {
			return false
		}
	}
	return true
}
