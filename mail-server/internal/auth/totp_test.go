package auth_test

import (
	"testing"
	"time"

	"mailanchor/serverd/internal/totp"
)

// code computes the current TOTP for a secret (what the authenticator app would show).
func code(t *testing.T, secret string) string {
	t.Helper()
	c, err := totp.Code(secret, time.Now())
	if err != nil {
		t.Fatalf("totp.Code: %v", err)
	}
	return c
}

// Full R0001 stage-4 flow: an enrolled-but-not-activated secret does not gate login; once
// activated, login requires a valid X-TOTP-Code.
func TestTOTPEnrollActivateAndLoginGate(t *testing.T) {
	svc, store := newSvc(t)
	u, err := store.CreateUser("2fa@example.com", "s3cr3t-pass", "TFA")
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}

	// Enroll. Before activation, login still works with password alone and is not gated.
	setup, err := svc.TOTPSetup(u.ID)
	if err != nil {
		t.Fatalf("setup: %v", err)
	}
	if len(setup.RecoveryCodes) != 8 || setup.Secret == "" || setup.OTPAuthURL == "" {
		t.Fatalf("setup payload incomplete: %+v", setup)
	}
	if svc.TOTPStatus(u.ID) {
		t.Fatal("status should be false before activation")
	}
	if _, requires2FA, lerr := svc.LoginWithTOTP("2fa@example.com", "s3cr3t-pass", "", "1.1.1.1"); lerr != nil || requires2FA {
		t.Fatalf("pre-activation login should not be gated: requires2FA=%v err=%v", requires2FA, lerr)
	}

	// Activate with a wrong code -> rejected; status stays off.
	if err := svc.TOTPActivate(u.ID, "000000"); codeOf(err) != "TWO_FACTOR_INVALID" {
		t.Fatalf("activate wrong code: want TWO_FACTOR_INVALID, got %v", err)
	}
	// Activate with the right code.
	if err := svc.TOTPActivate(u.ID, code(t, setup.Secret)); err != nil {
		t.Fatalf("activate: %v", err)
	}
	if !svc.TOTPStatus(u.ID) {
		t.Fatal("status should be true after activation")
	}

	// Now login without a code must return requires2FA (and no tokens).
	res, requires2FA, err := svc.LoginWithTOTP("2fa@example.com", "s3cr3t-pass", "", "1.1.1.1")
	if err != nil || !requires2FA {
		t.Fatalf("activated login w/o code: want requires2FA, got requires2FA=%v err=%v", requires2FA, err)
	}
	if res.AccessToken != "" {
		t.Fatal("no access token should be issued when 2FA is pending")
	}
	// Wrong code -> TWO_FACTOR_INVALID.
	if _, _, err := svc.LoginWithTOTP("2fa@example.com", "s3cr3t-pass", "999999", "1.1.1.1"); codeOf(err) != "TWO_FACTOR_INVALID" {
		t.Fatalf("login wrong code: want TWO_FACTOR_INVALID, got %v", err)
	}
	// Right code -> tokens issued.
	res, requires2FA, err = svc.LoginWithTOTP("2fa@example.com", "s3cr3t-pass", code(t, setup.Secret), "1.1.1.1")
	if err != nil || requires2FA || res.AccessToken == "" {
		t.Fatalf("login with valid code failed: requires2FA=%v err=%v token=%q", requires2FA, err, res.AccessToken)
	}
}

// A recovery code logs the user in once and is then consumed (single-use).
func TestTOTPRecoveryCodeSingleUse(t *testing.T) {
	svc, store := newSvc(t)
	u, _ := store.CreateUser("rec@example.com", "s3cr3t-pass", "REC")
	setup, _ := svc.TOTPSetup(u.ID)
	if err := svc.TOTPActivate(u.ID, code(t, setup.Secret)); err != nil {
		t.Fatalf("activate: %v", err)
	}

	rc := setup.RecoveryCodes[0]
	if _, _, err := svc.LoginWithTOTP("rec@example.com", "s3cr3t-pass", rc, "2.2.2.2"); err != nil {
		t.Fatalf("login with recovery code failed: %v", err)
	}
	// Reusing the same recovery code must now fail.
	if _, _, err := svc.LoginWithTOTP("rec@example.com", "s3cr3t-pass", rc, "2.2.2.2"); codeOf(err) != "TWO_FACTOR_INVALID" {
		t.Fatalf("reused recovery code: want TWO_FACTOR_INVALID, got %v", err)
	}
}

// Disable requires a valid current code and removes the gate; regenerate replaces the set.
func TestTOTPDisableAndRegenerate(t *testing.T) {
	svc, store := newSvc(t)
	u, _ := store.CreateUser("dis@example.com", "s3cr3t-pass", "DIS")
	setup, _ := svc.TOTPSetup(u.ID)
	if err := svc.TOTPActivate(u.ID, code(t, setup.Secret)); err != nil {
		t.Fatalf("activate: %v", err)
	}

	// Regenerate recovery codes (verify with current TOTP); new set differs from the old.
	newCodes, err := svc.TOTPRegenerateRecovery(u.ID, code(t, setup.Secret))
	if err != nil {
		t.Fatalf("regenerate: %v", err)
	}
	if len(newCodes) != 8 || newCodes[0] == setup.RecoveryCodes[0] {
		t.Fatalf("recovery codes not rotated: %v vs %v", newCodes, setup.RecoveryCodes)
	}
	// An old recovery code must no longer work for login.
	if _, _, err := svc.LoginWithTOTP("dis@example.com", "s3cr3t-pass", setup.RecoveryCodes[1], "3.3.3.3"); codeOf(err) != "TWO_FACTOR_INVALID" {
		t.Fatalf("old recovery code after regen: want TWO_FACTOR_INVALID, got %v", err)
	}

	// Disable with a wrong code -> rejected, still enabled.
	if err := svc.TOTPDisable(u.ID, "000000"); codeOf(err) != "TWO_FACTOR_INVALID" {
		t.Fatalf("disable wrong code: want TWO_FACTOR_INVALID, got %v", err)
	}
	if !svc.TOTPStatus(u.ID) {
		t.Fatal("still enabled after failed disable")
	}
	// Disable with a valid code -> removed; login no longer gated.
	if err := svc.TOTPDisable(u.ID, code(t, setup.Secret)); err != nil {
		t.Fatalf("disable: %v", err)
	}
	if svc.TOTPStatus(u.ID) {
		t.Fatal("status should be false after disable")
	}
	if _, requires2FA, err := svc.LoginWithTOTP("dis@example.com", "s3cr3t-pass", "", "3.3.3.3"); err != nil || requires2FA {
		t.Fatalf("post-disable login should not be gated: requires2FA=%v err=%v", requires2FA, err)
	}
}

// Re-enrolling (setup again) overwrites the prior secret, matching auth2fa reset semantics.
func TestTOTPResetupOverwrites(t *testing.T) {
	svc, store := newSvc(t)
	u, _ := store.CreateUser("re@example.com", "s3cr3t-pass", "RE")
	first, _ := svc.TOTPSetup(u.ID)
	second, _ := svc.TOTPSetup(u.ID)
	if first.Secret == second.Secret {
		t.Fatal("re-setup should mint a new secret")
	}
	// The first secret's code must not activate the second enrollment.
	if err := svc.TOTPActivate(u.ID, code(t, first.Secret)); codeOf(err) != "TWO_FACTOR_INVALID" {
		t.Fatalf("stale secret should not activate: got %v", err)
	}
	if err := svc.TOTPActivate(u.ID, code(t, second.Secret)); err != nil {
		t.Fatalf("activate with current secret: %v", err)
	}
}
