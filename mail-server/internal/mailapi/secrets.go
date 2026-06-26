package mailapi

import "sync"

// MemSecretStore is an in-memory SecretStore (dev/default). Production must use an
// encrypted-at-rest store (DB0008 §2.3: raw credentials live in secret storage). Credentials are kept
// out of SQL deliberately; this impl simply does not persist them.
type MemSecretStore struct {
	mu sync.RWMutex
	m  map[string]Credential
}

// NewMemSecretStore returns an empty in-memory secret store.
func NewMemSecretStore() *MemSecretStore { return &MemSecretStore{m: map[string]Credential{}} }

func (s *MemSecretStore) Get(ref string) (Credential, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	c, ok := s.m[ref]
	return c, ok
}

func (s *MemSecretStore) Put(ref string, cred Credential) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.m[ref] = cred
}

func (s *MemSecretStore) Delete(ref string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.m, ref)
}
