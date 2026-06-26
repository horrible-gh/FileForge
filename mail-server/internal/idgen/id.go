// Package idgen mints opaque, server-issued identifiers.
// DB0008: every PK is an opaque prefixed TEXT (u_/rt_/acc_/lbl_/m_/d_/a_/t_).
// P0007 notation rule: clients treat identifiers as opaque.
package idgen

import (
	"crypto/rand"
	"encoding/base32"
	"strings"
)

// Prefixes per DB0008.
const (
	User         = "u_"
	RefreshToken = "rt_"
	Account      = "acc_"
	Label        = "lbl_"
	Mail         = "m_"
	Draft        = "d_"
	Attachment   = "a_"
	Thread       = "t_"
)

var enc = base32.StdEncoding.WithPadding(base32.NoPadding)

// New returns a new opaque identifier with the given prefix.
func New(prefix string) string {
	var b [15]byte // 15 bytes -> 24 base32 chars
	if _, err := rand.Read(b[:]); err != nil {
		panic("idgen: entropy source failed: " + err.Error())
	}
	return prefix + strings.ToLower(enc.EncodeToString(b[:]))
}
