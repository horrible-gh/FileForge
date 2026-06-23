package auth

import (
	"sync"
	"time"

	"mailanchor/serverd/internal/apperr"
	"mailanchor/serverd/internal/idgen"
)

// Service implements the auth module logic (L0011) on top of the cross-cutting
// token-rotation rules (L0010).
type Service struct {
	store      *Store
	secret     []byte
	accessTTL  time.Duration
	refreshTTL time.Duration
	lock       *lockout
	federated  *FederatedVerifier // optional FileForge RS256 bridge (mailanchor.ui.0003 T1)
}

func NewService(store *Store, secret []byte, accessTTL, refreshTTL time.Duration) *Service {
	return &Service{
		store:      store,
		secret:     secret,
		accessTTL:  accessTTL,
		refreshTTL: refreshTTL,
		lock:       newLockout(),
	}
}

// WithFederation enables the FileForge token bridge: tokens that fail local HS256
// verification are then tried as RS256 FileForge tokens, provisioning a local user on
// first sight. Returns the receiver for chaining; a nil verifier leaves the bridge off.
func (s *Service) WithFederation(v *FederatedVerifier) *Service {
	s.federated = v
	return s
}

type UserPublic struct {
	UserID      string `json:"user_id"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
}

type LoginResult struct {
	AccessToken  string     `json:"access_token"`
	RefreshToken string     `json:"refresh_token"`
	TokenType    string     `json:"token_type"`
	ExpiresIn    int        `json:"expires_in"`
	User         UserPublic `json:"user"`
}

type RefreshResult struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int    `json:"expires_in"`
}

type SessionResult struct {
	User          UserPublic `json:"user"`
	Authenticated bool       `json:"authenticated"`
}

// Login validates credentials and issues an access+refresh pair (L0011 §2.1).
func (s *Service) Login(email, password, clientIP string) (LoginResult, error) {
	key := email + "|" + clientIP
	if s.lock.isLocked(key) {
		return LoginResult{}, apperr.AuthInvalidCreds // lockout concealed behind same code
	}

	user, err := s.store.FindUserByEmail(email)
	if err != nil {
		if IsNotFound(err) {
			VerifyPassword(password, DummyHash) // equalize timing for unknown account
			s.lock.record(key)
			return LoginResult{}, apperr.AuthInvalidCreds
		}
		return LoginResult{}, apperr.Internal
	}
	if !VerifyPassword(password, user.PasswordHash) {
		s.lock.record(key)
		return LoginResult{}, apperr.AuthInvalidCreds
	}

	s.lock.clear(key)
	access, rerr := IssueAccess(s.secret, user.ID, s.accessTTL)
	if rerr != nil {
		return LoginResult{}, apperr.Internal
	}
	raw, ierr := s.issueRefresh(user.ID, nil)
	if ierr != nil {
		return LoginResult{}, apperr.Internal
	}
	return LoginResult{
		AccessToken:  access,
		RefreshToken: raw,
		TokenType:    "Bearer",
		ExpiresIn:    int(s.accessTTL.Seconds()),
		User:         UserPublic{UserID: user.ID, Email: user.Email, DisplayName: user.DisplayName},
	}, nil
}

// Refresh rotates a refresh token and mints a new access token (L0010 §2.1).
func (s *Service) Refresh(presented string) (RefreshResult, error) {
	row, err := s.store.FindRefreshByHash(hashRefresh(presented))
	if err != nil {
		if IsNotFound(err) {
			return RefreshResult{}, apperr.TokenInvalid // unissued / forged
		}
		return RefreshResult{}, apperr.Internal
	}
	now := nowUTC()
	if row.RevokedAt != nil {
		// Reuse of a revoked token = theft suspicion -> revoke whole chain (L0010 §2.1.1).
		_ = s.store.RevokeUserChain(row.UserID, now)
		return RefreshResult{}, apperr.TokenInvalid
	}
	if now.After(row.ExpiresAt.Add(clockSkewAllowance)) {
		_ = s.store.RevokeRefresh(row.TokenID, now)
		return RefreshResult{}, apperr.TokenInvalid
	}

	// Normal — rotate atomically: revoke previous + issue successor in one transaction
	// (NR0011 B6). raw/hash for the successor are minted here so the raw token can be
	// returned; the store performs the conditional revoke + insert.
	raw, hash := newRefreshSecret()
	next := RefreshRow{
		TokenID:     idgen.New(idgen.RefreshToken),
		UserID:      row.UserID,
		TokenHash:   hash,
		IssuedAt:    now,
		ExpiresAt:   now.Add(s.refreshTTL),
		RotatedFrom: &row.TokenID,
	}
	ok, rerr := s.store.RotateRefresh(row.TokenID, next, now)
	if rerr != nil {
		return RefreshResult{}, apperr.Internal
	}
	if !ok {
		// A concurrent Refresh already rotated this token between our read and write —
		// the same reuse/theft signal as a presented-but-revoked token. Nuke the chain.
		_ = s.store.RevokeUserChain(row.UserID, now)
		return RefreshResult{}, apperr.TokenInvalid
	}
	access, aerr := IssueAccess(s.secret, row.UserID, s.accessTTL)
	if aerr != nil {
		return RefreshResult{}, apperr.Internal
	}
	return RefreshResult{
		AccessToken:  access,
		RefreshToken: raw,
		TokenType:    "Bearer",
		ExpiresIn:    int(s.accessTTL.Seconds()),
	}, nil
}

// Logout revokes the presented refresh token. Idempotent; always succeeds (L0011 §2.3).
func (s *Service) Logout(presented string) error {
	row, err := s.store.FindRefreshByHash(hashRefresh(presented))
	if err == nil && row.RevokedAt == nil {
		_ = s.store.RevokeRefresh(row.TokenID, nowUTC())
	}
	return nil // always 204, token state concealed
}

// Session validates the access token and returns the current user (L0011 §2.2).
func (s *Service) Session(accessToken string) (SessionResult, error) {
	user, err := s.resolveAccess(accessToken)
	if err != nil {
		return SessionResult{}, err
	}
	return SessionResult{
		User:          UserPublic{UserID: user.ID, Email: user.Email, DisplayName: user.DisplayName},
		Authenticated: true,
	}, nil
}

// AuthenticateAccess is used by the middleware to resolve a bearer token to a user id.
func (s *Service) AuthenticateAccess(accessToken string) (string, error) {
	user, err := s.resolveAccess(accessToken)
	if err != nil {
		return "", err
	}
	return user.ID, nil
}

// resolveAccess maps a bearer access token to a local user. It first tries the
// self-issued HS256 path; if that fails *invalid* (not expired) and the FileForge
// bridge is configured, it retries as an RS256 FileForge token, just-in-time
// provisioning the linked local user (mailanchor.ui.0003 T1). HS256 expiry is returned
// as-is (the client should refresh) and never reinterpreted as a foreign token.
func (s *Service) resolveAccess(accessToken string) (User, error) {
	userID, err := VerifyAccess(s.secret, accessToken)
	if err == nil {
		user, ferr := s.store.FindUserByID(userID)
		if ferr != nil {
			return User{}, apperr.TokenInvalid // issued then deleted, etc.
		}
		return user, nil
	}
	if IsExpired(err) {
		return User{}, apperr.TokenExpired
	}
	if s.federated != nil {
		if user, ferr := s.resolveFederated(accessToken); ferr == nil {
			return user, nil
		} else if IsExpired(ferr) {
			return User{}, apperr.TokenExpired
		}
	}
	return User{}, apperr.TokenInvalid
}

// resolveFederated verifies a FileForge RS256 token and resolves it to a local user,
// provisioning one on first sight. The returned error preserves expiry semantics so the
// caller can surface TOKEN_EXPIRED for a stale FileForge token.
func (s *Service) resolveFederated(accessToken string) (User, error) {
	claims, err := s.federated.Verify(accessToken)
	if err != nil {
		return User{}, err
	}
	user, perr := s.store.ProvisionExternalUser(claims.Subject, claims.Email, claims.DisplayName)
	if perr != nil {
		return User{}, apperr.Internal
	}
	return user, nil
}

func (s *Service) issueRefresh(userID string, rotatedFrom *string) (string, error) {
	raw, hash := newRefreshSecret()
	now := nowUTC()
	err := s.store.InsertRefresh(RefreshRow{
		TokenID:     idgen.New(idgen.RefreshToken),
		UserID:      userID,
		TokenHash:   hash,
		IssuedAt:    now,
		ExpiresAt:   now.Add(s.refreshTTL),
		RotatedFrom: rotatedFrom,
	})
	if err != nil {
		return "", err
	}
	return raw, nil
}

// --- login lockout (L0011 §2.5) — in-memory sliding window (storage DEFERRED) ---

const (
	lockWindow = 15 * time.Minute
	lockMax    = 5
)

type lockout struct {
	mu       sync.Mutex
	failures map[string][]time.Time
}

func newLockout() *lockout { return &lockout{failures: make(map[string][]time.Time)} }

func (l *lockout) record(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.failures[key] = append(l.prune(key), time.Now())
}

func (l *lockout) isLocked(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.prune(key)) >= lockMax
}

func (l *lockout) clear(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.failures, key)
}

// prune drops failures outside the window; caller holds the lock.
func (l *lockout) prune(key string) []time.Time {
	cutoff := time.Now().Add(-lockWindow)
	kept := l.failures[key][:0]
	for _, t := range l.failures[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	l.failures[key] = kept
	return kept
}
