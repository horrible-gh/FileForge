package auth

import (
	"database/sql"
	"errors"
	"time"

	"mailanchor/serverd/internal/idgen"
)

// Store is the persistence boundary for the auth module (app_user, refresh_token).
type Store struct{ db *sql.DB }

func NewStore(db *sql.DB) *Store { return &Store{db: db} }

type User struct {
	ID           string
	Email        string
	PasswordHash string
	DisplayName  string
}

type RefreshRow struct {
	TokenID     string
	UserID      string
	TokenHash   string
	IssuedAt    time.Time
	ExpiresAt   time.Time
	RevokedAt   *time.Time
	RotatedFrom *string
}

const tsLayout = "2006-01-02T15:04:05Z"

func nowUTC() time.Time { return time.Now().UTC().Truncate(time.Second) }

// CreateUser inserts an app_user and seeds the per-user system labels and settings row
// in one transaction (DB0008 §3 backfill note). Signup itself is DEFERRED (L0011);
// this is used by the dev seed and tests.
func (s *Store) CreateUser(email, plainPassword, displayName string) (User, error) {
	hash, err := HashPassword(plainPassword)
	if err != nil {
		return User{}, err
	}
	u := User{ID: idgen.New(idgen.User), Email: email, PasswordHash: hash, DisplayName: displayName}
	if err := s.insertSeededUser(u, ""); err != nil {
		return User{}, err
	}
	return u, nil
}

// insertSeededUser inserts an app_user plus its system labels and settings row in one
// transaction (DB0008 §3 backfill note). externalSubject, when non-empty, links the row
// to a FileForge identity (mailanchor.ui.0003 T1); empty for local-password users.
func (s *Store) insertSeededUser(u User, externalSubject string) error {
	now := nowUTC().Format(tsLayout)
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck

	if _, err := tx.Exec(
		`INSERT INTO app_user(user_id,email,password_hash,display_name,external_subject,created_at,updated_at)
		 VALUES(?,?,?,?,?,?,?)`,
		u.ID, u.Email, u.PasswordHash, nullStr(u.DisplayName), nullStr(externalSubject), now, now); err != nil {
		return err
	}
	for _, sys := range []string{"inbox", "sent", "draft"} {
		if _, err := tx.Exec(
			`INSERT INTO label(label_id,user_id,name,type,color,created_at) VALUES(?,?,?, 'system', NULL, ?)`,
			sys+"_"+u.ID, u.ID, sys, now); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(`INSERT INTO user_settings(user_id) VALUES(?)`, u.ID); err != nil {
		return err
	}
	return tx.Commit()
}

// FindUserByExternalSubject resolves the local user linked to a FileForge subject, or
// sql.ErrNoRows when none is linked yet (mailanchor.ui.0003 T1).
func (s *Store) FindUserByExternalSubject(subject string) (User, error) {
	return s.scanUser(s.db.QueryRow(
		`SELECT user_id,email,password_hash,COALESCE(display_name,'')
		 FROM app_user WHERE external_subject=?`, subject))
}

// ProvisionExternalUser just-in-time creates (or returns the already-linked) local user
// for a FileForge token subject. It is idempotent: concurrent first-requests for the
// same subject collapse onto one row via the partial unique index on external_subject.
//
// FileForge today emits only {sub, exp}, so email/displayName are best-effort. A missing
// email is synthesized deterministically from the subject so the app_user UNIQUE(email)
// invariant holds without a network round-trip back to FileForge. The local password is
// a random unusable hash — these users authenticate only through the FileForge bridge.
func (s *Store) ProvisionExternalUser(subject, email, displayName string) (User, error) {
	if u, err := s.FindUserByExternalSubject(subject); err == nil {
		return u, nil
	} else if !IsNotFound(err) {
		return User{}, err
	}
	if email == "" {
		email = "fileforge+" + subject + "@federated.local"
	}
	hash, err := HashPassword("rt_" + subject) // never used for login; argon2id keeps the column honest
	if err != nil {
		return User{}, err
	}
	u := User{ID: idgen.New(idgen.User), Email: email, PasswordHash: hash, DisplayName: displayName}
	if err := s.insertSeededUser(u, subject); err != nil {
		// A concurrent request linked the subject (or the email) first — re-resolve.
		if linked, ferr := s.FindUserByExternalSubject(subject); ferr == nil {
			return linked, nil
		}
		return User{}, err
	}
	return u, nil
}

func (s *Store) FindUserByEmail(email string) (User, error) {
	return s.scanUser(s.db.QueryRow(
		`SELECT user_id,email,password_hash,COALESCE(display_name,'') FROM app_user WHERE email=?`, email))
}

func (s *Store) FindUserByID(id string) (User, error) {
	return s.scanUser(s.db.QueryRow(
		`SELECT user_id,email,password_hash,COALESCE(display_name,'') FROM app_user WHERE user_id=?`, id))
}

func (s *Store) scanUser(row *sql.Row) (User, error) {
	var u User
	if err := row.Scan(&u.ID, &u.Email, &u.PasswordHash, &u.DisplayName); err != nil {
		return User{}, err
	}
	return u, nil
}

func (s *Store) InsertRefresh(r RefreshRow) error {
	_, err := s.db.Exec(
		`INSERT INTO refresh_token(token_id,user_id,token_hash,issued_at,expires_at,revoked_at,rotated_from)
		 VALUES(?,?,?,?,?,?,?)`,
		r.TokenID, r.UserID, r.TokenHash,
		r.IssuedAt.Format(tsLayout), r.ExpiresAt.Format(tsLayout),
		tsPtr(r.RevokedAt), r.RotatedFrom)
	return err
}

// FindRefreshByHash returns the row or sql.ErrNoRows.
func (s *Store) FindRefreshByHash(hash string) (RefreshRow, error) {
	var (
		r       RefreshRow
		issued  string
		expires string
		revoked sql.NullString
		rotated sql.NullString
	)
	err := s.db.QueryRow(
		`SELECT token_id,user_id,token_hash,issued_at,expires_at,revoked_at,rotated_from
		 FROM refresh_token WHERE token_hash=?`, hash).
		Scan(&r.TokenID, &r.UserID, &r.TokenHash, &issued, &expires, &revoked, &rotated)
	if err != nil {
		return RefreshRow{}, err
	}
	r.IssuedAt, _ = time.Parse(tsLayout, issued)
	r.ExpiresAt, _ = time.Parse(tsLayout, expires)
	if revoked.Valid {
		if t, perr := time.Parse(tsLayout, revoked.String); perr == nil {
			r.RevokedAt = &t
		}
	}
	if rotated.Valid {
		r.RotatedFrom = &rotated.String
	}
	return r, nil
}

func (s *Store) RevokeRefresh(tokenID string, at time.Time) error {
	_, err := s.db.Exec(`UPDATE refresh_token SET revoked_at=? WHERE token_id=? AND revoked_at IS NULL`,
		at.Format(tsLayout), tokenID)
	return err
}

// RotateRefresh atomically revokes the presented token and inserts its successor in one
// transaction (NR0011 B6). The revoke is conditional (revoked_at IS NULL); if it affects
// 0 rows another concurrent Refresh already rotated this token, so we roll back and
// return ok=false (the caller treats that as reuse/theft). This closes the non-atomic
// window where the old token could be revoked but the new one never issued (silent
// logout), and where two concurrent refreshes could both fork a chain from one token.
func (s *Store) RotateRefresh(oldTokenID string, next RefreshRow, at time.Time) (bool, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return false, err
	}
	defer tx.Rollback() //nolint:errcheck

	res, err := tx.Exec(`UPDATE refresh_token SET revoked_at=? WHERE token_id=? AND revoked_at IS NULL`,
		at.Format(tsLayout), oldTokenID)
	if err != nil {
		return false, err
	}
	if n, _ := res.RowsAffected(); n != 1 {
		return false, nil // already rotated/revoked concurrently
	}
	if _, err := tx.Exec(
		`INSERT INTO refresh_token(token_id,user_id,token_hash,issued_at,expires_at,revoked_at,rotated_from)
		 VALUES(?,?,?,?,?,?,?)`,
		next.TokenID, next.UserID, next.TokenHash,
		next.IssuedAt.Format(tsLayout), next.ExpiresAt.Format(tsLayout),
		tsPtr(next.RevokedAt), next.RotatedFrom); err != nil {
		return false, err
	}
	if err := tx.Commit(); err != nil {
		return false, err
	}
	return true, nil
}

// RevokeUserChain revokes every active refresh token for the user (reuse detection,
// L0010 §2.1.1).
func (s *Store) RevokeUserChain(userID string, at time.Time) error {
	_, err := s.db.Exec(`UPDATE refresh_token SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL`,
		at.Format(tsLayout), userID)
	return err
}

// IsNotFound reports whether err is a "no rows" sentinel.
func IsNotFound(err error) bool { return errors.Is(err, sql.ErrNoRows) }

func nullStr(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func tsPtr(t *time.Time) any {
	if t == nil {
		return nil
	}
	return t.Format(tsLayout)
}
