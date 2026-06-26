package auth

import (
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"os"
	"sync"

	"github.com/golang-jwt/jwt/v5"
)

// FederatedClaims is the subset of a FileForge-issued token the bridge consumes.
// Subject is the FileForge user id (the JWT `sub`), used as the stable external key.
// Email/DisplayName are best-effort: present when FileForge embeds them, otherwise the
// provisioner synthesizes a deterministic placeholder from Subject.
type FederatedClaims struct {
	Subject     string
	Email       string
	DisplayName string
}

// FederatedVerifier validates RS256 access tokens minted by FileForge against its
// public key (mailanchor.ui.0003 T1). Only the public key crosses the polyglot
// boundary, so the Go server can verify FileForge tokens without sharing a secret.
//
// It is intentionally permissive about claim *shape* (FileForge today emits only
// {sub, exp}) but strict about signature + algorithm + expiry, and enforces iss/aud
// when the deployment configures expected values.
type FederatedVerifier struct {
	parser   *jwt.Parser
	issuer   string
	audience string

	// Key material. Either pub is set eagerly (inline PEM / file readable at boot), or
	// keyFile is set and pub is resolved lazily on first use and cached. The lazy path
	// makes the bridge self-healing against the 0017 NR0003 boot-order race: a Go server
	// that started before FileForge generated jwt_public.pem now picks the key up on the
	// next federated request instead of staying disabled until a manual restart.
	mu      sync.RWMutex
	pub     *rsa.PublicKey
	keyFile string
}

// newFederatedParser builds the shared JWT parser (RS256-only, iss/aud enforced when set).
func newFederatedParser(issuer, audience string) *jwt.Parser {
	opts := []jwt.ParserOption{
		jwt.WithValidMethods([]string{"RS256"}),
		jwt.WithLeeway(clockSkewAllowance),
	}
	if issuer != "" {
		opts = append(opts, jwt.WithIssuer(issuer))
	}
	if audience != "" {
		opts = append(opts, jwt.WithAudience(audience))
	}
	return jwt.NewParser(opts...)
}

// NewFederatedVerifier builds a verifier from a PEM-encoded RSA public key (PKIX or
// PKCS1). issuer/audience, when non-empty, are required to match the token claims.
func NewFederatedVerifier(pubPEM []byte, issuer, audience string) (*FederatedVerifier, error) {
	pub, err := parseRSAPublicKey(pubPEM)
	if err != nil {
		return nil, err
	}
	return &FederatedVerifier{
		pub:      pub,
		parser:   newFederatedParser(issuer, audience),
		issuer:   issuer,
		audience: audience,
	}, nil
}

// NewLazyFederatedVerifier builds a verifier whose RSA public key is read+parsed from
// keyFile on first use (and cached once successful) rather than at construction. It never
// fails to construct: when the file does not yet exist, Verify returns an invalid-token
// error (the request 401s) and a later request — after the key appears — succeeds. This is
// the 0017 NR0003 hardening for the boot-order race; keyFile should be an absolute path.
func NewLazyFederatedVerifier(keyFile, issuer, audience string) *FederatedVerifier {
	return &FederatedVerifier{
		parser:   newFederatedParser(issuer, audience),
		issuer:   issuer,
		audience: audience,
		keyFile:  keyFile,
	}
}

// resolveKey returns the RSA public key, loading it lazily from keyFile on first use and
// caching it. A cached key short-circuits under a read lock; the slow path takes the write
// lock and re-checks so concurrent first-requests load the file at most once.
func (v *FederatedVerifier) resolveKey() (*rsa.PublicKey, error) {
	v.mu.RLock()
	if v.pub != nil {
		k := v.pub
		v.mu.RUnlock()
		return k, nil
	}
	v.mu.RUnlock()

	if v.keyFile == "" {
		return nil, errors.New("fileforge pubkey: not configured")
	}

	v.mu.Lock()
	defer v.mu.Unlock()
	if v.pub != nil { // another goroutine won the race
		return v.pub, nil
	}
	body, err := os.ReadFile(v.keyFile)
	if err != nil {
		return nil, fmt.Errorf("fileforge pubkey: read %s: %w", v.keyFile, err)
	}
	pub, err := parseRSAPublicKey(body)
	if err != nil {
		return nil, err
	}
	v.pub = pub
	return pub, nil
}

// Ready reports whether the public key is currently loadable, attempting a lazy load if
// needed. Used by /healthz so a lazily-armed bridge reports "enabled" once the key appears.
func (v *FederatedVerifier) Ready() bool {
	_, err := v.resolveKey()
	return err == nil
}

// Status returns the /healthz bridge state: "enabled" once the key is loaded/loadable,
// otherwise "pending" (configured but the key file is not yet readable).
func (v *FederatedVerifier) Status() string {
	if v.Ready() {
		return "enabled"
	}
	return "pending"
}

// federatedRawClaims mirrors the claims FileForge may emit. MapClaims is avoided so the
// registered-claim validators (exp/iss/aud) run via jwt's typed path.
type federatedRawClaims struct {
	jwt.RegisteredClaims
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
	Name        string `json:"name"`
}

// Verify validates the token and returns the federated claims. The error mirrors the
// HS256 path: expiry is distinguishable (-> TOKEN_EXPIRED, client refreshes) from any
// other failure (-> TOKEN_INVALID, re-login).
func (v *FederatedVerifier) Verify(token string) (FederatedClaims, error) {
	pub, err := v.resolveKey()
	if err != nil {
		// Key not yet available (lazy bridge, key file not readable). Treat as an invalid
		// token so the request 401s now; a later request after the key appears succeeds.
		return FederatedClaims{}, &accessVerifyError{expired: false}
	}
	var rc federatedRawClaims
	if _, err := v.parser.ParseWithClaims(token, &rc, func(t *jwt.Token) (any, error) {
		return pub, nil
	}); err != nil {
		return FederatedClaims{}, &accessVerifyError{expired: errors.Is(err, jwt.ErrTokenExpired)}
	}
	if rc.Subject == "" {
		return FederatedClaims{}, &accessVerifyError{expired: false} // a token with no subject can't be mapped
	}
	display := rc.DisplayName
	if display == "" {
		display = rc.Name
	}
	return FederatedClaims{Subject: rc.Subject, Email: rc.Email, DisplayName: display}, nil
}

// parseRSAPublicKey accepts a PKIX ("PUBLIC KEY") or PKCS1 ("RSA PUBLIC KEY") PEM block.
func parseRSAPublicKey(pemBytes []byte) (*rsa.PublicKey, error) {
	block, _ := pem.Decode(pemBytes)
	if block == nil {
		return nil, errors.New("fileforge pubkey: no PEM block found")
	}
	if key, err := x509.ParsePKIXPublicKey(block.Bytes); err == nil {
		if rsaKey, ok := key.(*rsa.PublicKey); ok {
			return rsaKey, nil
		}
		return nil, errors.New("fileforge pubkey: PKIX key is not RSA")
	}
	if rsaKey, err := x509.ParsePKCS1PublicKey(block.Bytes); err == nil {
		return rsaKey, nil
	}
	return nil, fmt.Errorf("fileforge pubkey: unsupported PEM block %q (want PKIX or PKCS1 RSA)", block.Type)
}
