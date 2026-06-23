package mailapi

import (
	"sync"
	"time"
)

// OAuthStateStore persists the one-time anti-CSRF `state` issued by AuthorizeURL until the
// provider redirects the user's browser back to OAuthCallback. The callback arrives
// UNAUTHENTICATED (a browser redirect carries no JWT), so the user identity + provider are
// recovered from the state rather than a token — this is the front-channel "closer" the
// FileForge build was missing (server.0005 NR0009 gap A; MailAnchor backs the same binding
// with a Redis state->user map). Take consumes the state once (single-use) and entries
// expire after a TTL so a leaked/abandoned state cannot be replayed.
type OAuthStateStore interface {
	// Put binds an issued state to the user that started the flow and the chosen provider.
	Put(state, userID, provider string)
	// Take returns the binding for a state and removes it (single-use). ok=false when the
	// state is unknown, already consumed, or expired.
	Take(state string) (userID, provider string, ok bool)
}

// stateTTL bounds how long an issued authorize state stays valid. Long enough for a human
// consent round-trip, short enough to cap replay (mirrors MailAnchor's 10-minute Redis TTL).
const stateTTL = 10 * time.Minute

type stateEntry struct {
	userID   string
	provider string
	expires  time.Time
}

// MemStateStore is an in-memory OAuthStateStore (dev/default; single-process). A multi-
// instance production deployment must back this with a shared store (e.g. Redis) so the
// authorize and callback half-steps can land on different instances — the same swap point
// as MemSecretStore.
type MemStateStore struct {
	mu  sync.Mutex
	m   map[string]stateEntry
	now func() time.Time
}

// NewMemStateStore returns an empty in-memory state store using the real clock.
func NewMemStateStore() *MemStateStore {
	return &MemStateStore{m: map[string]stateEntry{}, now: time.Now}
}

func (s *MemStateStore) Put(state, userID, provider string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sweep()
	s.m[state] = stateEntry{userID: userID, provider: provider, expires: s.now().Add(stateTTL)}
}

func (s *MemStateStore) Take(state string) (string, string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.m[state]
	if !ok {
		return "", "", false
	}
	delete(s.m, state) // single-use: consume even if expired
	if s.now().After(e.expires) {
		return "", "", false
	}
	return e.userID, e.provider, true
}

// sweep drops expired entries opportunistically (called under lock from Put) so an
// abandoned-consent flow does not leak state entries indefinitely.
func (s *MemStateStore) sweep() {
	now := s.now()
	for k, e := range s.m {
		if now.After(e.expires) {
			delete(s.m, k)
		}
	}
}
