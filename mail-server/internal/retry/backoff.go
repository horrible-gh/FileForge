// Package retry implements the L0010 §2.4 transient-error backoff used by the
// send (L0012 §2.4) and sync (L0013 §2.2/§2.4) external calls.
//
// Defaults follow L0010 §1: base=1s, factor=2, max=30s, ±20% jitter, with a
// bounded number of attempts (transient_retry_max). Permanent errors (wrapped via
// Permanent) are not retried — they surface immediately.
package retry

import (
	"errors"
	"math/rand"
	"time"
)

// Policy bounds a with-backoff retry loop.
type Policy struct {
	MaxAttempts int           // total attempts incl. the first (transient_retry_max + 1)
	Base        time.Duration // first backoff (L0010 base=1s)
	Factor      float64       // multiplier per attempt (L0010 factor=2)
	Max         time.Duration // backoff cap (L0010 max=30s)
	Jitter      float64       // ±fraction jitter (L0010 ±20% -> 0.2)
}

// Default is the L0010 §1 policy.
func Default() Policy {
	return Policy{MaxAttempts: 4, Base: time.Second, Factor: 2, Max: 30 * time.Second, Jitter: 0.2}
}

// permanent marks an error that must not be retried (e.g. external auth failure ->
// reauth_required, which the caller maps without burning retries).
type permanent struct{ err error }

func (p permanent) Error() string { return p.err.Error() }
func (p permanent) Unwrap() error { return p.err }

// Permanent wraps err so Do stops immediately instead of retrying.
func Permanent(err error) error { return permanent{err: err} }

// IsPermanent reports whether err (or a wrapped cause) is permanent.
func IsPermanent(err error) bool {
	var p permanent
	return errors.As(err, &p)
}

// Delay computes the backoff for a 1-based attempt number (attempt 1 -> ~Base),
// applying the exponential growth, cap, and symmetric jitter.
func (p Policy) Delay(attempt int, rng func() float64) time.Duration {
	if attempt < 1 {
		attempt = 1
	}
	d := float64(p.Base)
	for i := 1; i < attempt; i++ {
		d *= p.Factor
		if d >= float64(p.Max) {
			d = float64(p.Max)
			break
		}
	}
	if d > float64(p.Max) {
		d = float64(p.Max)
	}
	if p.Jitter > 0 && rng != nil {
		// rng() in [0,1) -> factor in [1-jitter, 1+jitter)
		d *= 1 + p.Jitter*(2*rng()-1)
	}
	if d < 0 {
		d = 0
	}
	return time.Duration(d)
}

// Do runs fn with backoff. sleep is injectable for tests (nil -> time.Sleep).
// It returns the last error once attempts are exhausted, or immediately on a
// Permanent error. fn returning nil stops the loop (success).
func (p Policy) Do(fn func() error, sleep func(time.Duration)) error {
	if sleep == nil {
		sleep = time.Sleep
	}
	if p.MaxAttempts < 1 {
		p.MaxAttempts = 1
	}
	var last error
	for attempt := 1; attempt <= p.MaxAttempts; attempt++ {
		err := fn()
		if err == nil {
			return nil
		}
		last = err
		if IsPermanent(err) {
			return err
		}
		if attempt < p.MaxAttempts {
			sleep(p.Delay(attempt, rand.Float64))
		}
	}
	return last
}
