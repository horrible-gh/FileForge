package sharedstore

import (
	"sync"
	"time"
)

// MemStore is the in-process Store used when no Redis is configured. It still gives real
// single-instance semantics (logout revokes a live access token within this process,
// which the previous stateless-only design could not do at all). Multi-instance
// deployments should configure Redis so revocation/state is shared.
type MemStore struct {
	mu   sync.Mutex
	data map[string]entry
	// now is injectable for deterministic tests; defaults to time.Now.
	now func() time.Time
}

type entry struct {
	value  string
	expiry time.Time // zero == no expiry
}

// NewMemStore returns an empty in-process store.
func NewMemStore() *MemStore {
	return &MemStore{data: make(map[string]entry), now: time.Now}
}

func (m *MemStore) clock() time.Time {
	if m.now != nil {
		return m.now()
	}
	return time.Now()
}

// set stores value with an optional ttl, sweeping expired keys opportunistically.
func (m *MemStore) set(key, value string, ttl time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var exp time.Time
	if ttl > 0 {
		exp = m.clock().Add(ttl)
	}
	m.data[key] = entry{value: value, expiry: exp}
}

// get returns the live value for key, deleting it if del is true (single-use). Expired
// entries are treated as absent and removed.
func (m *MemStore) get(key string, del bool) (string, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	e, ok := m.data[key]
	if !ok {
		return "", false
	}
	if !e.expiry.IsZero() && !m.clock().Before(e.expiry) {
		delete(m.data, key)
		return "", false
	}
	if del {
		delete(m.data, key)
	}
	return e.value, true
}

func (m *MemStore) Blacklist(tokenHash string, ttl time.Duration) error {
	if ttl <= 0 {
		return nil
	}
	m.set(blacklistPrefix+tokenHash, "1", ttl)
	return nil
}

func (m *MemStore) IsBlacklisted(tokenHash string) (bool, error) {
	_, ok := m.get(blacklistPrefix+tokenHash, false)
	return ok, nil
}

func (m *MemStore) PutState(key, value string, ttl time.Duration) error {
	m.set(statePrefix+key, value, ttl)
	return nil
}

func (m *MemStore) TakeState(key string) (string, bool, error) {
	v, ok := m.get(statePrefix+key, true)
	return v, ok, nil
}

func (m *MemStore) Close() error { return nil }
