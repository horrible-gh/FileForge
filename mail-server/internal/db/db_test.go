package db

import (
	"database/sql"
	"os"
	"path/filepath"
	"strconv"
	"testing"
)

// TestNormalizeDriver maps the FileForge DBType aliases onto the two Go dialects and
// rejects unsupported types loudly (R0001 stage 1: DB_TYPE branch mysql/sqlite).
func TestNormalizeDriver(t *testing.T) {
	cases := map[string]string{
		"":        DriverSQLite,
		"sqlite":  DriverSQLite,
		"sqlite3": DriverSQLite,
		"local":   DriverSQLite,
		"SQLite":  DriverSQLite,
		"mysql":   DriverMySQL,
		"MySQL":   DriverMySQL,
		" mysql ": DriverMySQL,
	}
	for in, want := range cases {
		got, err := NormalizeDriver(in)
		if err != nil {
			t.Fatalf("NormalizeDriver(%q) unexpected err: %v", in, err)
		}
		if got != want {
			t.Fatalf("NormalizeDriver(%q) = %q, want %q", in, got, want)
		}
	}
	if _, err := NormalizeDriver("postgresql"); err == nil {
		t.Fatal("NormalizeDriver(postgresql) must error (unsupported in the Go sidecar)")
	}
}

// TestMigrationDialectParity guards against drift: every SQLite migration must have a
// same-named MySQL counterpart and vice versa, so DB_TYPE switches never apply a
// different number/version of migrations.
func TestMigrationDialectParity(t *testing.T) {
	read := func(driver string) map[string]bool {
		entries, err := migrationFS.ReadDir("migrations/" + driver)
		if err != nil {
			t.Fatalf("read migrations/%s: %v", driver, err)
		}
		set := map[string]bool{}
		for _, e := range entries {
			if !e.IsDir() && filepath.Ext(e.Name()) == ".sql" {
				set[e.Name()] = true
			}
		}
		return set
	}
	sqlite := read(DriverSQLite)
	mysql := read(DriverMySQL)
	if len(sqlite) == 0 {
		t.Fatal("no sqlite migrations embedded")
	}
	if len(sqlite) != len(mysql) {
		t.Fatalf("migration count mismatch: sqlite=%d mysql=%d", len(sqlite), len(mysql))
	}
	for name := range sqlite {
		if !mysql[name] {
			t.Errorf("sqlite migration %q has no mysql counterpart", name)
		}
	}
	for name := range mysql {
		if !sqlite[name] {
			t.Errorf("mysql migration %q has no sqlite counterpart", name)
		}
	}
}

// TestSQLiteOpenAndMigrate confirms the dialect-aware Open still boots SQLite and applies
// all migrations (schema_migrations row count == embedded file count).
func TestSQLiteOpenAndMigrate(t *testing.T) {
	conn, err := Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer conn.Close()
	assertAllMigrationsApplied(t, conn, DriverSQLite)
}

// TestMySQLOpenAndMigrate is the live "mysql startup text" gate (R0001 stage 1 done
// criterion). It is skipped unless MAILANCHOR_TEST_MYSQL_HOST is set, so the default
// `go test ./...` needs no MySQL. When pointed at a MySQL/MariaDB server it runs the
// real migration chain through OpenDB and verifies every migration applied.
func TestMySQLOpenAndMigrate(t *testing.T) {
	host := os.Getenv("MAILANCHOR_TEST_MYSQL_HOST")
	if host == "" {
		t.Skip("set MAILANCHOR_TEST_MYSQL_HOST to run the live MySQL migration test")
	}
	port, _ := strconv.Atoi(os.Getenv("MAILANCHOR_TEST_MYSQL_PORT"))
	cfg := Config{
		Driver:   DriverMySQL,
		Host:     host,
		Port:     port,
		User:     getenvOr("MAILANCHOR_TEST_MYSQL_USER", "root"),
		Password: os.Getenv("MAILANCHOR_TEST_MYSQL_PASSWORD"),
		Database: getenvOr("MAILANCHOR_TEST_MYSQL_DB", "mailanchor_t"),
	}
	conn, err := OpenDB(cfg)
	if err != nil {
		t.Fatalf("OpenDB(mysql): %v", err)
	}
	defer conn.Close()
	assertAllMigrationsApplied(t, conn, DriverMySQL)

	// Idempotency: a second OpenDB must apply nothing new and still succeed.
	conn2, err := OpenDB(cfg)
	if err != nil {
		t.Fatalf("OpenDB(mysql) second boot: %v", err)
	}
	conn2.Close()
}

// assertAllMigrationsApplied checks schema_migrations recorded exactly one row per
// embedded migration file for the driver, proving the full chain ran.
func assertAllMigrationsApplied(t *testing.T, conn *sql.DB, driver string) {
	t.Helper()
	entries, err := migrationFS.ReadDir("migrations/" + driver)
	if err != nil {
		t.Fatalf("read migrations/%s: %v", driver, err)
	}
	want := 0
	for _, e := range entries {
		if !e.IsDir() && filepath.Ext(e.Name()) == ".sql" {
			want++
		}
	}
	var got int
	if err := conn.QueryRow(`SELECT COUNT(*) FROM schema_migrations`).Scan(&got); err != nil {
		t.Fatalf("count schema_migrations: %v", err)
	}
	if got != want {
		t.Fatalf("%s: applied %d migrations, want %d", driver, got, want)
	}
}

func getenvOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
