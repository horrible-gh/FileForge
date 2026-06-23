// Package sharedstore is the cross-cutting ephemeral key store R0001 stage 3 aligns with
// the FileForge/MailAnchor redis_client convention. It backs two concerns:
//
//	token blacklist  — blacklist:{tokenHash}  (logout revokes a still-valid access token)
//	ephemeral state  — state:{key}            (OAuth CSRF state, 2FA pending — stage 4)
//
// Two implementations satisfy Store: MemStore (in-process default, single instance) and
// RedisStore (go-redis, shared across instances when REDIS_* is configured). The Store
// abstraction lets the auth service blacklist tokens without importing a redis client,
// mirroring the codebase's ports+fakes pattern (Sender/ChangeSource/OAuth).
package sharedstore

import "time"

// Key prefixes match the Python originals (FileForge: blacklist:{token}; MailAnchor:
// gmail_oauth_state:{state}). We namespace generic state under state:.
const (
	blacklistPrefix = "blacklist:"
	statePrefix     = "state:"
)

// Store is the shared ephemeral store contract.
type Store interface {
	// Blacklist marks tokenHash as revoked for ttl (logout). A non-positive ttl is a no-op
	// (the token is already past expiry, so stateless verification rejects it anyway).
	Blacklist(tokenHash string, ttl time.Duration) error
	// IsBlacklisted reports whether tokenHash is currently blacklisted.
	IsBlacklisted(tokenHash string) (bool, error)

	// PutState stores value under key for ttl (OAuth state / 2FA pending).
	PutState(key, value string, ttl time.Duration) error
	// TakeState atomically reads and deletes key (single-use semantics). ok is false when
	// the key is absent or expired.
	TakeState(key string) (value string, ok bool, err error)

	// Close releases any backing resources (no-op for MemStore).
	Close() error
}
