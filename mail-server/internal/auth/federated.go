package auth

import (
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"

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
	pub      *rsa.PublicKey
	parser   *jwt.Parser
	issuer   string
	audience string
}

// NewFederatedVerifier builds a verifier from a PEM-encoded RSA public key (PKIX or
// PKCS1). issuer/audience, when non-empty, are required to match the token claims.
func NewFederatedVerifier(pubPEM []byte, issuer, audience string) (*FederatedVerifier, error) {
	pub, err := parseRSAPublicKey(pubPEM)
	if err != nil {
		return nil, err
	}
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
	return &FederatedVerifier{
		pub:      pub,
		parser:   jwt.NewParser(opts...),
		issuer:   issuer,
		audience: audience,
	}, nil
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
	var rc federatedRawClaims
	if _, err := v.parser.ParseWithClaims(token, &rc, func(t *jwt.Token) (any, error) {
		return v.pub, nil
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
