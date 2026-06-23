package retry

import (
	"errors"
	"testing"
	"time"
)

func TestDoRetriesTransientThenSucceeds(t *testing.T) {
	p := Policy{MaxAttempts: 3, Base: 0, Factor: 2, Max: 0}
	calls := 0
	err := p.Do(func() error {
		calls++
		if calls < 3 {
			return errors.New("transient")
		}
		return nil
	}, func(time.Duration) {})
	if err != nil {
		t.Fatalf("want success, got %v", err)
	}
	if calls != 3 {
		t.Fatalf("want 3 attempts, got %d", calls)
	}
}

func TestDoStopsOnPermanent(t *testing.T) {
	p := Default()
	calls := 0
	sentinel := errors.New("boom")
	err := p.Do(func() error {
		calls++
		return Permanent(sentinel)
	}, func(time.Duration) {})
	if calls != 1 {
		t.Fatalf("permanent must not retry: calls=%d", calls)
	}
	if !errors.Is(err, sentinel) {
		t.Fatalf("permanent must unwrap to cause: %v", err)
	}
	if !IsPermanent(err) {
		t.Fatalf("IsPermanent should report true")
	}
}

func TestDoExhaustsAndReturnsLast(t *testing.T) {
	p := Policy{MaxAttempts: 2, Base: 0}
	calls := 0
	want := errors.New("still failing")
	err := p.Do(func() error { calls++; return want }, func(time.Duration) {})
	if calls != 2 || !errors.Is(err, want) {
		t.Fatalf("calls=%d err=%v", calls, err)
	}
}

func TestDelayGrowsAndCaps(t *testing.T) {
	p := Policy{Base: time.Second, Factor: 2, Max: 4 * time.Second}
	noJitter := func() float64 { return 0.5 } // 2*0.5-1 = 0 -> no jitter shift
	got := []time.Duration{
		p.Delay(1, noJitter), p.Delay(2, noJitter), p.Delay(3, noJitter), p.Delay(4, noJitter),
	}
	want := []time.Duration{1 * time.Second, 2 * time.Second, 4 * time.Second, 4 * time.Second}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("delay[%d]=%v want %v", i+1, got[i], want[i])
		}
	}
}
