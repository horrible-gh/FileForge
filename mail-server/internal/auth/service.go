package auth

import (
	"sync"
	"time"

	"mailanchor/serverd/internal/apperr"
	"mailanchor/serverd/internal/idgen"
	"mailanchor/serverd/internal/sharedstore"
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
	// shared is the token-blacklist / state store (R0001 stage 3). Defaults to an
	// in-process MemStore so logout revokes a live access token even without Redis;
	// WithSharedStore swaps in a Redis-backed store for multi-instance deployments.
	shared sharedstore.Store
	// totp implements the second factor (R0001 stage 4). Always present; gates login only
	// for users who have activated TOTP.
	totp *TOTPManager
}

func NewService(store *Store, secret []byte, accessTTL, refreshTTL time.Duration) *Service {
	return &Service{
		store:      store,
		secret:     secret,
		accessTTL:  accessTTL,
		refreshTTL: refreshTTL,
		lock:       newLockout(),
		shared:     sharedstore.NewMemStore(),
		totp:       newTOTPManager(store),
	}
}

// WithSharedStore overrides the default in-process blacklist/state store (e.g. with a
// Redis-backed one). A nil store is ignored. Returns the receiver for chaining.
func (s *Service) WithSharedStore(store sharedstore.Store) *Service {
	if store != nil {
		s.shared = store
	}
	return s
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

// Login validates credentials and issues an access+refresh pair (L0011 §2.1). It is the
// no-second-factor entry point (kept for callers/tests that don't supply a TOTP code); a
// user who has activated 2FA must use LoginWithTOTP.
func (s *Service) Login(email, password, clientIP string) (LoginResult, error) {
	res, _, err := s.login(email, password, "", clientIP)
	return res, err
}

// LoginWithTOTP is the 2FA-aware login (R0001 stage 4). When the account has activated TOTP
// and totpCode is empty, it returns requires2FA=true with an empty result and a nil error —
// the client must resubmit with the X-TOTP-Code header. A wrong code returns
// apperr.TwoFactorInvalid; absent 2FA, totpCode is ignored.
func (s *Service) LoginWithTOTP(email, password, totpCode, clientIP string) (LoginResult, bool, error) {
	return s.login(email, password, totpCode, clientIP)
}

func (s *Service) login(email, password, totpCode, clientIP string) (LoginResult, bool, error) {
	key := email + "|" + clientIP
	if s.lock.isLocked(key) {
		return LoginResult{}, false, apperr.AuthInvalidCreds // lockout concealed behind same code
	}

	user, err := s.store.FindUserByEmail(email)
	if err != nil {
		if IsNotFound(err) {
			VerifyPassword(password, DummyHash) // equalize timing for unknown account
			s.lock.record(key)
			return LoginResult{}, false, apperr.AuthInvalidCreds
		}
		return LoginResult{}, false, apperr.Internal
	}
	if !VerifyPassword(password, user.PasswordHash) {
		s.lock.record(key)
		return LoginResult{}, false, apperr.AuthInvalidCreds
	}

	// Second factor (R0001 stage 4): a correct password is necessary but not sufficient when
	// the user has activated TOTP. We keep the failure window armed (don't clear the lockout)
	// until the second factor passes, so a leaked password alone stays bounded.
	if s.totp != nil && s.totp.IsEnabled(user.ID) {
		if totpCode == "" {
			return LoginResult{}, true, nil // tell the client to resubmit with X-TOTP-Code
		}
		if !s.totp.Verify(user.ID, totpCode) {
			s.lock.record(key)
			return LoginResult{}, false, apperr.TwoFactorInvalid
		}
	}

	s.lock.clear(key)
	access, rerr := IssueAccess(s.secret, user.ID, s.accessTTL)
	if rerr != nil {
		return LoginResult{}, false, apperr.Internal
	}
	raw, ierr := s.issueRefresh(user.ID, nil)
	if ierr != nil {
		return LoginResult{}, false, apperr.Internal
	}
	return LoginResult{
		AccessToken:  access,
		RefreshToken: raw,
		TokenType:    "Bearer",
		ExpiresIn:    int(s.accessTTL.Seconds()),
		User:         UserPublic{UserID: user.ID, Email: user.Email, DisplayName: user.DisplayName},
	}, false, nil
}

// --- 2FA (TOTP) service surface (R0001 stage 4). Thin delegations to the TOTPManager so the
// HTTP handlers depend only on *Service. ---

// TOTPStatus reports whether the user has activated 2FA.
func (s *Service) TOTPStatus(userID string) bool { return s.totp.IsEnabled(userID) }

// TOTPSetup enrolls (or re-enrolls) a secret and returns the QR/recovery payload.
func (s *Service) TOTPSetup(userID string) (TOTPSetup, error) { return s.totp.Setup(userID) }

// TOTPActivate flips an enrolled secret to active after verifying a current code.
func (s *Service) TOTPActivate(userID, code string) error { return s.totp.Activate(userID, code) }

// TOTPDisable removes 2FA after verifying a current code.
func (s *Service) TOTPDisable(userID, code string) error { return s.totp.Disable(userID, code) }

// TOTPRegenerateRecovery issues a fresh set of recovery codes after verifying a current code.
func (s *Service) TOTPRegenerateRecovery(userID, code string) ([]string, error) {
	return s.totp.RegenerateRecovery(userID, code)
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

// BlacklistAccess revokes a still-valid access token in real time (R0001 stage 3 token
// blacklist). The stateless access token cannot otherwise be invalidated before its
// expiry; logout registers it in the shared store keyed by its hash, for the remainder of
// its lifetime, and resolveAccess rejects any token found there. A blank/already-expired
// token is a no-op. Best-effort: a shared-store error is swallowed (logout always 204).
func (s *Service) BlacklistAccess(accessToken string) {
	if accessToken == "" || s.shared == nil {
		return
	}
	ttl := s.accessTTL // safe upper bound (covers federated tokens we can't introspect)
	if exp, ok := accessExp(s.secret, accessToken); ok {
		ttl = time.Until(exp) + clockSkewAllowance
	}
	if ttl > 0 {
		_ = s.shared.Blacklist(tokenKey(accessToken), ttl)
	}
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
	// Token blacklist (R0001 stage 3): a token revoked at logout is rejected before any
	// signature work, for both self-issued and federated tokens.
	if s.shared != nil {
		if bl, _ := s.shared.IsBlacklisted(tokenKey(accessToken)); bl {
			return User{}, apperr.TokenInvalid
		}
	}
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
