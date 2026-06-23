// Package storage is the object-store backend for attachment bytes (DB0008 §2.7:
// attachment metadata lives in SQL, the bytes live behind a storage_ref key).
// The interface keeps the byte backend swappable (disk now, S3/object store later
// per NR0003 §5 / L0012 DEFERRED) without touching the mail/draft transaction logic.
package storage

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"path/filepath"
)

// ErrNotFound is returned when a storage_ref has no backing object.
var ErrNotFound = errors.New("storage: object not found")

// Blob is the attachment byte backend. A storage_ref is an opaque key minted by
// Put and stored in attachment.storage_ref; Get/Delete address bytes by that key.
type Blob interface {
	// Put streams r into a new object and returns its opaque storage_ref and size.
	Put(r io.Reader) (ref string, size int64, err error)
	// Open returns a reader for the bytes at ref (ErrNotFound if absent). Caller closes.
	Open(ref string) (io.ReadCloser, error)
	// Delete removes the object at ref. Missing ref is not an error (idempotent).
	Delete(ref string) error
}

// DiskStore is a Blob backed by a directory. Objects are content-addressed by a
// random key fanned out into two-char subdirs to avoid huge flat directories.
type DiskStore struct{ root string }

// NewDiskStore creates (if needed) the root directory and returns a disk-backed Blob.
func NewDiskStore(root string) (*DiskStore, error) {
	if err := os.MkdirAll(root, 0o755); err != nil {
		return nil, err
	}
	return &DiskStore{root: root}, nil
}

func (d *DiskStore) path(ref string) string {
	// ref is hex; fan out on the first two chars. Guard against path traversal by
	// only ever using the minted hex (no caller-supplied separators).
	if len(ref) < 2 {
		return filepath.Join(d.root, "_", ref)
	}
	return filepath.Join(d.root, ref[:2], ref)
}

func (d *DiskStore) Put(r io.Reader) (string, int64, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", 0, err
	}
	ref := hex.EncodeToString(b[:])
	p := d.path(ref)
	dir := filepath.Dir(p)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", 0, err
	}
	// Atomic publish (NR0011 B10): stream into a temp file, fsync, then rename into place.
	// A crash mid-copy leaves only the temp file — never a truncated object at the live ref
	// (the previous os.Create wrote directly to the final path).
	f, err := os.CreateTemp(dir, ".tmp-*")
	if err != nil {
		return "", 0, err
	}
	tmp := f.Name()
	n, err := io.Copy(f, r)
	if err == nil {
		err = f.Sync() // durability before the rename publishes the object
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		_ = os.Remove(tmp)
		return "", 0, err
	}
	if err := os.Rename(tmp, p); err != nil {
		_ = os.Remove(tmp)
		return "", 0, err
	}
	return ref, n, nil
}

func (d *DiskStore) Open(ref string) (io.ReadCloser, error) {
	f, err := os.Open(d.path(ref))
	if os.IsNotExist(err) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return f, nil
}

func (d *DiskStore) Delete(ref string) error {
	err := os.Remove(d.path(ref))
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}
