package auth

import (
	"net/http"
	"testing"
)

// NR0011 S3: clientIP must ignore client-supplied X-Forwarded-For so an attacker cannot
// rotate it to evade the per-IP login lockout. XFF trust is opt-in via chi RealIP
// (cfg.TrustProxy), which rewrites RemoteAddr upstream of this function.
func TestClientIPIgnoresXFF(t *testing.T) {
	r, _ := http.NewRequest(http.MethodPost, "/auth/login", nil)
	r.RemoteAddr = "10.0.0.5:54321"
	r.Header.Set("X-Forwarded-For", "1.2.3.4, 5.6.7.8")

	if got := clientIP(r); got != "10.0.0.5" {
		t.Fatalf("clientIP must use RemoteAddr, not XFF; got %q", got)
	}

	// rotating XFF must not change the lockout key
	r.Header.Set("X-Forwarded-For", "9.9.9.9")
	if got := clientIP(r); got != "10.0.0.5" {
		t.Fatalf("rotated XFF leaked into clientIP: %q", got)
	}
}
