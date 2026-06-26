package storage

import (
	"bytes"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// NR0011 B10: Put publishes atomically (temp + rename), so no partial/temp file is left
// alongside the final object after a successful write.
func TestDiskStorePutLeavesNoTempFile(t *testing.T) {
	root := t.TempDir()
	s, err := NewDiskStore(root)
	if err != nil {
		t.Fatalf("NewDiskStore: %v", err)
	}
	ref, _, err := s.Put(bytes.NewReader([]byte("payload")))
	if err != nil {
		t.Fatalf("Put: %v", err)
	}
	dir := filepath.Join(root, ref[:2])
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".tmp-") {
			t.Fatalf("temp file leaked: %s", e.Name())
		}
	}
	if len(entries) != 1 || entries[0].Name() != ref {
		t.Fatalf("expected exactly the object %q, got %v", ref, entries)
	}
}

func TestDiskStoreRoundTrip(t *testing.T) {
	s, err := NewDiskStore(t.TempDir())
	if err != nil {
		t.Fatalf("NewDiskStore: %v", err)
	}
	payload := []byte("attachment bytes text")
	ref, n, err := s.Put(bytes.NewReader(payload))
	if err != nil {
		t.Fatalf("Put: %v", err)
	}
	if n != int64(len(payload)) || ref == "" {
		t.Fatalf("Put size/ref: n=%d ref=%q", n, ref)
	}
	rc, err := s.Open(ref)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	got, _ := io.ReadAll(rc)
	rc.Close()
	if !bytes.Equal(got, payload) {
		t.Fatalf("round-trip mismatch: %q", got)
	}

	if err := s.Delete(ref); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if _, err := s.Open(ref); !errors.Is(err, ErrNotFound) {
		t.Fatalf("want ErrNotFound after delete, got %v", err)
	}
	// delete is idempotent
	if err := s.Delete(ref); err != nil {
		t.Fatalf("idempotent Delete: %v", err)
	}
}

func TestDiskStoreOpenMissing(t *testing.T) {
	s, _ := NewDiskStore(t.TempDir())
	if _, err := s.Open("deadbeef"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}
}
