package mailapi

import (
	"encoding/json"
	"time"

	"mailanchor/serverd/internal/sharedstore"
)

// SharedStateStore backs the OAuth front-channel `state` with the cross-instance shared store
// (R0001 stage 5: "OAuth state의 sharedstore 이관"). MemStateStore is single-process, so a
// multi-instance deployment could issue the authorize state on one instance and receive the
// callback on another, losing the binding; routing it through the shared store (Redis when
// configured) lets the two half-steps land anywhere. Single-use + TTL are provided by the
// shared store's atomic TakeState (read+delete) and PutState ttl — the same anti-replay
// guarantees MemStateStore gave, now shared.
type SharedStateStore struct {
	store sharedstore.Store
	ttl   time.Duration
}

// NewSharedStateStore wraps a shared store as an OAuthStateStore, reusing the same state TTL
// as the in-memory implementation.
func NewSharedStateStore(store sharedstore.Store) *SharedStateStore {
	return &SharedStateStore{store: store, ttl: stateTTL}
}

// sharedStateValue is the JSON binding stored under a state key (compact field names since
// this is an ephemeral value, not a public payload).
type sharedStateValue struct {
	UserID   string `json:"u"`
	Provider string `json:"p"`
}

func (s *SharedStateStore) Put(state, userID, provider string) {
	raw, err := json.Marshal(sharedStateValue{UserID: userID, Provider: provider})
	if err != nil {
		return
	}
	_ = s.store.PutState(state, string(raw), s.ttl)
}

func (s *SharedStateStore) Take(state string) (string, string, bool) {
	raw, ok, err := s.store.TakeState(state)
	if err != nil || !ok {
		return "", "", false
	}
	var v sharedStateValue
	if err := json.Unmarshal([]byte(raw), &v); err != nil {
		return "", "", false
	}
	return v.UserID, v.Provider, true
}

// compile-time assertion that SharedStateStore satisfies the port.
var _ OAuthStateStore = (*SharedStateStore)(nil)
