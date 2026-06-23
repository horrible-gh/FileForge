// Package db opens the application database (SQLite or MySQL) and runs the DB0008
// migration chain. Migrations are dialect-separated (migrations/sqlite, migrations/mysql)
// mirroring the FileForge/MailAnchor Python convention (res/sql/migration/{sqlite,mysql}).
package db

import (
	"database/sql"
	"embed"
	"fmt"
	"net/url"
	"sort"
	"strings"

	_ "github.com/go-sql-driver/mysql" // pure-Go MySQL driver
	_ "modernc.org/sqlite"             // pure-Go SQLite driver (no cgo -> single static binary)
)

//go:embed migrations/sqlite/*.sql migrations/mysql/*.sql
var migrationFS embed.FS

// Driver identifies the supported SQL backends. The Python originals branch on a wider
// DBType enum (mysql|sqlite|sqlite3|local|postgresql); the Go sidecar supports the two
// dialects R0001 names (mysql/sqlite). NormalizeDriver maps the aliases.
const (
	DriverSQLite = "sqlite"
	DriverMySQL  = "mysql"
)

// Config carries the resolved DB connection parameters (config stage 1/2).
type Config struct {
	Driver   string // "sqlite" | "mysql" (already normalized)
	Path     string // sqlite file path (DB_PATH)
	Host     string // mysql host (DB_HOST)
	Port     int    // mysql port (DB_PORT; 0 -> 3306)
	User     string // mysql user (DB_USER)
	Password string // mysql password (DB_PASSWORD)
	Database string // mysql database (DB_DATABASE)
}

// NormalizeDriver maps the FileForge DBType aliases onto the two supported Go dialects.
// Unknown/unsupported types (e.g. postgresql) return an error rather than silently
// falling back, so a misconfigured DB_TYPE fails loudly at boot.
func NormalizeDriver(dbType string) (string, error) {
	switch strings.ToLower(strings.TrimSpace(dbType)) {
	case "", "sqlite", "sqlite3", "local":
		return DriverSQLite, nil
	case "mysql":
		return DriverMySQL, nil
	default:
		return "", fmt.Errorf("unsupported DB_TYPE %q (supported: sqlite, mysql)", dbType)
	}
}

// Open opens an SQLite database at path (convenience wrapper used by tests and the
// default sqlite deployment). It is equivalent to OpenDB with a sqlite Config.
func Open(path string) (*sql.DB, error) {
	return OpenDB(Config{Driver: DriverSQLite, Path: path})
}

// OpenDB opens the database for cfg.Driver, enables the dialect's integrity settings,
// and applies any pending migrations from the matching embedded directory.
func OpenDB(cfg Config) (*sql.DB, error) {
	switch cfg.Driver {
	case DriverSQLite:
		return openSQLite(cfg.Path)
	case DriverMySQL:
		return openMySQL(cfg)
	default:
		return nil, fmt.Errorf("db: unknown driver %q", cfg.Driver)
	}
}

func openSQLite(path string) (*sql.DB, error) {
	// modernc DSN: enable FK enforcement + busy timeout per connection.
	dsn := fmt.Sprintf("file:%s?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)", url.PathEscape(path))
	conn, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("open sqlite: %w", err)
	}
	// SQLite is single-writer; cap the pool to avoid "database is locked" churn.
	conn.SetMaxOpenConns(1)
	if err := conn.Ping(); err != nil {
		conn.Close()
		return nil, fmt.Errorf("ping sqlite: %w", err)
	}
	if err := migrate(conn, DriverSQLite); err != nil {
		conn.Close()
		return nil, err
	}
	return conn, nil
}

func openMySQL(cfg Config) (*sql.DB, error) {
	port := cfg.Port
	if port == 0 {
		port = 3306 // FileForge .env convention: DB_PORT=0 -> driver default
	}
	// multiStatements: several migrations bundle multiple statements in one file
	// (007 ALTER, 013/014 ALTER+UPDATE); go-sql-driver requires this to Exec them.
	// parseTime keeps DATETIME round-trips sane; utf8mb4 matches the table charset.
	dsn := fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?parseTime=true&multiStatements=true&charset=utf8mb4&collation=utf8mb4_unicode_ci",
		cfg.User, cfg.Password, cfg.Host, port, cfg.Database)
	conn, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("open mysql: %w", err)
	}
	if err := conn.Ping(); err != nil {
		conn.Close()
		return nil, fmt.Errorf("ping mysql (%s:%d/%s): %w", cfg.Host, port, cfg.Database, err)
	}
	if err := migrate(conn, DriverMySQL); err != nil {
		conn.Close()
		return nil, err
	}
	return conn, nil
}

// migrate applies the embedded migrations for driver in lexical order, tracked in
// schema_migrations. Each migration runs in its own transaction (additive per DB0008 §3).
func migrate(conn *sql.DB, driver string) error {
	if _, err := conn.Exec(schemaMigrationsDDL(driver)); err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}

	dir := "migrations/" + driver
	entries, err := migrationFS.ReadDir(dir)
	if err != nil {
		return err
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)

	for _, name := range names {
		var exists string
		err := conn.QueryRow(`SELECT version FROM schema_migrations WHERE version = ?`, name).Scan(&exists)
		if err == nil {
			continue // already applied
		}
		if err != sql.ErrNoRows {
			return fmt.Errorf("check migration %s: %w", name, err)
		}
		body, rerr := migrationFS.ReadFile(dir + "/" + name)
		if rerr != nil {
			return rerr
		}
		if aerr := applyOne(conn, name, string(body)); aerr != nil {
			return fmt.Errorf("apply %s: %w", name, aerr)
		}
	}
	return nil
}

// schemaMigrationsDDL returns the tracking-table DDL for the dialect. MySQL cannot
// PRIMARY KEY a TEXT column and has no strftime(); SQLite keeps its ISO-string default.
func schemaMigrationsDDL(driver string) string {
	if driver == DriverMySQL {
		return `CREATE TABLE IF NOT EXISTS schema_migrations (
			version    VARCHAR(255) NOT NULL PRIMARY KEY,
			applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`
	}
	return `CREATE TABLE IF NOT EXISTS schema_migrations (
		version    TEXT NOT NULL PRIMARY KEY,
		applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
	)`
}

func applyOne(conn *sql.DB, name, body string) error {
	tx, err := conn.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck // no-op after commit
	if _, err := tx.Exec(body); err != nil {
		return err
	}
	if _, err := tx.Exec(`INSERT INTO schema_migrations(version) VALUES(?)`, name); err != nil {
		return err
	}
	return tx.Commit()
}
