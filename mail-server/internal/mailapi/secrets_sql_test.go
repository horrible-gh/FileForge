package mailapi

import (
	"bytes"
	"path/filepath"
	"testing"
	"time"

	"mailanchor/serverd/internal/db"
)

func TestSQLSecretStorePersistsAcrossReopen(t *testing.T) {
	path := filepath.Join(t.TempDir(), "secrets.db")
	conn, err := db.Open(path)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	cred := Credential{
		AccessToken:  "ya29.SQL-ACCESS",
		RefreshToken: "1//SQL-REFRESH",
		Expiry:       time.Unix(1700000000, 0).UTC(),
	}
	NewSQLSecretStore(conn, []byte("secret-store-key")).Put("sec_1", cred)

	var blob []byte
	if err := conn.QueryRow(`SELECT credential_blob FROM oauth_secret WHERE oauth_ref=?`, "sec_1").Scan(&blob); err != nil {
		t.Fatalf("select blob: %v", err)
	}
	if bytes.Contains(blob, []byte("ya29.SQL-ACCESS")) || bytes.Contains(blob, []byte("1//SQL-REFRESH")) {
		t.Fatal("encrypted SQL secret blob contains plaintext token")
	}
	conn.Close()

	reopened, err := db.Open(path)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer reopened.Close()
	got, ok := NewSQLSecretStore(reopened, []byte("secret-store-key")).Get("sec_1")
	if !ok {
		t.Fatal("credential should survive DB reopen")
	}
	if got.AccessToken != cred.AccessToken || got.RefreshToken != cred.RefreshToken || !got.Expiry.Equal(cred.Expiry) {
		t.Fatalf("round-trip mismatch: %+v vs %+v", got, cred)
	}
}

func TestSQLSecretStorePlaintextDevModePersists(t *testing.T) {
	conn, err := db.Open(filepath.Join(t.TempDir(), "secrets-dev.db"))
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer conn.Close()

	store := NewSQLSecretStore(conn, nil)
	store.Put("sec_plain", Credential{AccessToken: "dev-access"})
	got, ok := store.Get("sec_plain")
	if !ok || got.AccessToken != "dev-access" {
		t.Fatalf("dev plaintext store get = %+v, %v", got, ok)
	}
	store.Delete("sec_plain")
	if _, ok := store.Get("sec_plain"); ok {
		t.Fatal("deleted secret should be absent")
	}
}

func TestSQLSecretStoreImplementsPort(t *testing.T) {
	var _ SecretStore = (*SQLSecretStore)(nil)
}
