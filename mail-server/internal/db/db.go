// Package db opens the SQLite database and runs the DB0008 migration chain.
package db

import (
	"database/sql"
	"embed"
	"fmt"
	"net/url"
	"sort"
	"strings"

	_ "modernc.org/sqlite" // pure-Go SQLite driver (no cgo -> single static binary)
)

//go:embed migrations/*.sql
var migrationFS embed.FS

// Open opens the SQLite database with foreign keys enabled and a busy timeout,
// then applies any pending migrations.
func Open(path string) (*sql.DB, error) {
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
	if err := migrate(conn); err != nil {
		conn.Close()
		return nil, err
	}
	return conn, nil
}

// migrate applies embedded migrations in lexical order, tracked in schema_migrations.
// Each migration runs in its own transaction (additive, reversible per DB0008 §3).
func migrate(conn *sql.DB) error {
	if _, err := conn.Exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
		version    TEXT NOT NULL PRIMARY KEY,
		applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
	)`); err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}

	entries, err := migrationFS.ReadDir("migrations")
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
		body, rerr := migrationFS.ReadFile("migrations/" + name)
		if rerr != nil {
			return rerr
		}
		if aerr := applyOne(conn, name, string(body)); aerr != nil {
			return fmt.Errorf("apply %s: %w", name, aerr)
		}
	}
	return nil
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
