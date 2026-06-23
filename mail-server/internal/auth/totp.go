package auth

import (
	"encoding/json"
	"strings"
	"time"

	"mailanchor/serverd/internal/apperr"
	"mailanchor/serverd/internal/totp"
)

// totpIssuer is the label shown in the authenticator app (otpauth issuer). Matches the
// MailAnchor auth2fa issuer convention.
const totpIssuer = "MailAnchor"

const (
	recoveryCodeCount  = 8
	recoveryCodeLength = 8
	totpVerifySkew     = 1 // ±1 step (±30s) clock-drift tolerance on login verification
)

// totpRecord mirrors a totp_auth row (R0001 stage 4). recovery_codes is stored as a JSON
// array in the TEXT column so the single-use semantics survive a round-trip without a
// dialect-specific array type.
type totpRecord struct {
	UserID        string
	Secret        string
	Enabled       bool
	RecoveryCodes []string
}

// TOTPSetup is the enrollment payload returned by Setup: the shared secret, the otpauth URI
// the client renders as a QR, and the one-time recovery codes (shown once).
type TOTPSetup struct {
	Secret        string   `json:"secret"`
	OTPAuthURL    string   `json:"otpauth_url"`
	RecoveryCodes []string `json:"recovery_codes"`
}

// TOTPManager implements the 2FA (TOTP) flows on top of the totp_auth table, mirroring the
// MailAnchor auth2fa lifecycle: setup -> activate -> (login) verify -> disable, plus
// recovery-code regeneration. A clock is injected so tests are deterministic.
type TOTPManager struct {
	store  *Store
	issuer string
	now    func() time.Time
}

func newTOTPManager(store *Store) *TOTPManager {
	return &TOTPManager{store: store, issuer: totpIssuer, now: time.Now}
}

// IsEnabled reports whether the user has an *activated* TOTP secret (an enrolled-but-not-yet-
// activated secret does not gate login). Any lookup error is treated as not-enabled so a
// totp_auth read failure never locks a user out of an otherwise valid login.
func (m *TOTPManager) IsEnabled(userID string) bool {
	rec, err := m.store.totpGet(userID)
	return err == nil && rec.Enabled
}

// Setup generates a fresh secret + recovery codes and stores them un-activated, overwriting
// any prior enrollment (matching auth2fa's reset-on-resetup behaviour). The account label in
// the otpauth URI is the user's email when known, else the user id.
func (m *TOTPManager) Setup(userID string) (TOTPSetup, error) {
	secret, err := totp.GenerateSecret()
	if err != nil {
		return TOTPSetup{}, apperr.Internal
	}
	codes, err := totp.GenerateRecoveryCodes(recoveryCodeCount, recoveryCodeLength)
	if err != nil {
		return TOTPSetup{}, apperr.Internal
	}
	account := userID
	if u, uerr := m.store.FindUserByID(userID); uerr == nil && u.Email != "" {
		account = u.Email
	}
	if err := m.store.totpUpsert(totpRecord{UserID: userID, Secret: secret, Enabled: false, RecoveryCodes: codes}); err != nil {
		return TOTPSetup{}, apperr.Internal
	}
	return TOTPSetup{
		Secret:        secret,
		OTPAuthURL:    totp.ProvisioningURI(secret, account, m.issuer),
		RecoveryCodes: codes,
	}, nil
}

// Activate flips an enrolled secret to active after the user proves possession by entering a
// current code from their app. Idempotent if already active. An invalid code -> TwoFactorInvalid.
func (m *TOTPManager) Activate(userID, code string) error {
	rec, err := m.store.totpGet(userID)
	if err != nil {
		if IsNotFound(err) {
			return apperr.ValidationFailed.WithDetails(map[string]any{"reason": "totp_not_configured"})
		}
		return apperr.Internal
	}
	if rec.Enabled {
		return nil
	}
	if !totp.Verify(rec.Secret, code, m.now(), totpVerifySkew) {
		return apperr.TwoFactorInvalid
	}
	rec.Enabled = true
	if err := m.store.totpUpsert(rec); err != nil {
		return apperr.Internal
	}
	return nil
}

// Verify checks a login-time code against the user's TOTP secret, then against the recovery
// codes; a matched recovery code is consumed (single-use). Returns false for an unknown user
// or any lookup error (fail closed — Login only calls this when IsEnabled is true).
func (m *TOTPManager) Verify(userID, code string) bool {
	rec, err := m.store.totpGet(userID)
	if err != nil {
		return false
	}
	if totp.Verify(rec.Secret, code, m.now(), totpVerifySkew) {
		return true
	}
	up := strings.ToUpper(strings.TrimSpace(code))
	if up == "" {
		return false
	}
	for i, rc := range rec.RecoveryCodes {
		if strings.ToUpper(rc) == up {
			rec.RecoveryCodes = append(append([]string{}, rec.RecoveryCodes[:i]...), rec.RecoveryCodes[i+1:]...)
			_ = m.store.totpUpsert(rec) // best-effort consume; a write failure just leaves it usable once more
			return true
		}
	}
	return false
}

// Disable removes the user's TOTP configuration after verifying a current code (so a stolen
// session cannot silently strip the second factor). An invalid code -> TwoFactorInvalid.
func (m *TOTPManager) Disable(userID, code string) error {
	if !m.Verify(userID, code) {
		return apperr.TwoFactorInvalid
	}
	if err := m.store.totpDelete(userID); err != nil {
		return apperr.Internal
	}
	return nil
}

// RegenerateRecovery issues a fresh set of recovery codes after verifying a current code,
// invalidating the previous set. Returns the new codes (shown once).
func (m *TOTPManager) RegenerateRecovery(userID, code string) ([]string, error) {
	if _, err := m.store.totpGet(userID); err != nil {
		if IsNotFound(err) {
			return nil, apperr.TwoFactorInvalid
		}
		return nil, apperr.Internal
	}
	if !m.Verify(userID, code) {
		return nil, apperr.TwoFactorInvalid
	}
	codes, err := totp.GenerateRecoveryCodes(recoveryCodeCount, recoveryCodeLength)
	if err != nil {
		return nil, apperr.Internal
	}
	rec, err := m.store.totpGet(userID)
	if err != nil {
		return nil, apperr.Internal
	}
	rec.RecoveryCodes = codes
	if err := m.store.totpUpsert(rec); err != nil {
		return nil, apperr.Internal
	}
	return codes, nil
}

// --- totp_auth persistence (Store) ---

// totpGet returns the user's totp_auth row or sql.ErrNoRows when unconfigured.
func (s *Store) totpGet(userID string) (totpRecord, error) {
	var (
		rec     totpRecord
		enabled int
		codes   string
	)
	err := s.db.QueryRow(
		`SELECT user_id,secret,enabled,COALESCE(recovery_codes,'') FROM totp_auth WHERE user_id=?`, userID).
		Scan(&rec.UserID, &rec.Secret, &enabled, &codes)
	if err != nil {
		return totpRecord{}, err
	}
	rec.Enabled = enabled != 0
	if codes != "" {
		_ = json.Unmarshal([]byte(codes), &rec.RecoveryCodes)
	}
	return rec, nil
}

// totpUpsert writes the record, preserving created_at on an existing row (UPDATE-then-INSERT
// rather than DELETE+INSERT). Portable across sqlite/mysql without ON CONFLICT/ON DUPLICATE.
func (s *Store) totpUpsert(rec totpRecord) error {
	enabled := 0
	if rec.Enabled {
		enabled = 1
	}
	raw, err := json.Marshal(rec.RecoveryCodes)
	if err != nil {
		return err
	}
	now := nowUTC().Format(tsLayout)
	res, err := s.db.Exec(
		`UPDATE totp_auth SET secret=?, enabled=?, recovery_codes=?, updated_at=? WHERE user_id=?`,
		rec.Secret, enabled, string(raw), now, rec.UserID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n > 0 {
		return nil
	}
	_, err = s.db.Exec(
		`INSERT INTO totp_auth(user_id,secret,enabled,recovery_codes,created_at,updated_at) VALUES(?,?,?,?,?,?)`,
		rec.UserID, rec.Secret, enabled, string(raw), now, now)
	return err
}

// totpDelete removes the user's totp_auth row (disable). Absent row is a no-op.
func (s *Store) totpDelete(userID string) error {
	_, err := s.db.Exec(`DELETE FROM totp_auth WHERE user_id=?`, userID)
	return err
}
