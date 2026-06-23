package sharedstore

import (
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
)

// storeContract exercises the behaviour every Store implementation must satisfy. It runs
// against both MemStore and a miniredis-backed RedisStore so the two stay in lock-step.
func storeContract(t *testing.T, s Store) {
	t.Helper()

	// blacklist round-trip
	if bl, err := s.IsBlacklisted("h1"); err != nil || bl {
		t.Fatalf("h1 should not be blacklisted yet (bl=%v err=%v)", bl, err)
	}
	if err := s.Blacklist("h1", time.Minute); err != nil {
		t.Fatalf("Blacklist: %v", err)
	}
	if bl, err := s.IsBlacklisted("h1"); err != nil || !bl {
		t.Fatalf("h1 must be blacklisted (bl=%v err=%v)", bl, err)
	}

	// non-positive ttl is a no-op
	if err := s.Blacklist("h2", 0); err != nil {
		t.Fatalf("Blacklist(0): %v", err)
	}
	if bl, _ := s.IsBlacklisted("h2"); bl {
		t.Fatal("ttl<=0 must not blacklist")
	}

	// state put + single-use take
	if err := s.PutState("k1", "v1", time.Minute); err != nil {
		t.Fatalf("PutState: %v", err)
	}
	v, ok, err := s.TakeState("k1")
	if err != nil || !ok || v != "v1" {
		t.Fatalf("TakeState first read: v=%q ok=%v err=%v", v, ok, err)
	}
	// second take must miss (single-use)
	if _, ok, _ := s.TakeState("k1"); ok {
		t.Fatal("TakeState must be single-use (second read should miss)")
	}
	// absent key
	if _, ok, _ := s.TakeState("nope"); ok {
		t.Fatal("absent key must report ok=false")
	}
}

func TestMemStoreContract(t *testing.T) {
	storeContract(t, NewMemStore())
}

func TestRedisStoreContract(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	defer mr.Close()
	s, err := NewRedisStore(Options{Host: mr.Host(), Port: atoiPort(t, mr.Port())})
	if err != nil {
		t.Fatalf("NewRedisStore: %v", err)
	}
	defer s.Close()
	storeContract(t, s)
}

// MemStore must honour TTL expiry using its injectable clock.
func TestMemStoreExpiry(t *testing.T) {
	m := NewMemStore()
	now := time.Unix(1_700_000_000, 0)
	m.now = func() time.Time { return now }

	_ = m.Blacklist("h", 10*time.Second)
	if bl, _ := m.IsBlacklisted("h"); !bl {
		t.Fatal("blacklisted before expiry")
	}
	now = now.Add(11 * time.Second) // advance past ttl
	if bl, _ := m.IsBlacklisted("h"); bl {
		t.Fatal("must expire after ttl")
	}
}

// RedisStore TTL is set on the key (verified via miniredis FastForward).
func TestRedisStoreExpiry(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	defer mr.Close()
	s, err := NewRedisStore(Options{Host: mr.Host(), Port: atoiPort(t, mr.Port())})
	if err != nil {
		t.Fatalf("NewRedisStore: %v", err)
	}
	defer s.Close()

	_ = s.Blacklist("h", 10*time.Second)
	if bl, _ := s.IsBlacklisted("h"); !bl {
		t.Fatal("blacklisted before expiry")
	}
	mr.FastForward(11 * time.Second)
	if bl, _ := s.IsBlacklisted("h"); bl {
		t.Fatal("redis key must expire after ttl")
	}
}

func TestNewRedisStoreEmptyHost(t *testing.T) {
	if _, err := NewRedisStore(Options{Host: ""}); err == nil {
		t.Fatal("empty host must error")
	}
}

func atoiPort(t *testing.T, p string) int {
	t.Helper()
	n := 0
	for _, c := range p {
		if c < '0' || c > '9' {
			t.Fatalf("bad port %q", p)
		}
		n = n*10 + int(c-'0')
	}
	return n
}
