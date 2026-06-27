// Command backfill-bodies is a one-time data migration that repairs mail bodies which
// were persisted *raw* before the receive-time decode step existed (R0001 / NR0003).
//
// The receive-time fix (imapx.extractBody) only affects mail fetched from now on; rows
// already in the DB keep their undecoded payload — raw base64 (e.g. "dGVzdA==") or
// untranscoded ISO-2022-JP. This tool sweeps mail.body_content through
// imapx.DecodeStoredBody (a conservative, header-less decoder) and rewrites only the rows
// it can confidently recover, leaving plaintext and ambiguous rows untouched.
//
// It ALSO regenerates mail.snippet — the short preview the mail *list* renders. The
// snippet is frozen at receive time, so old rows kept a snippet built from the raw
// (base64 / untranscoded ISO-2022-JP) body. Repairing only body_content fixed the
// opened-mail view but left the list still showing base64 / broken Japanese (0021 TR0008
// reject). For every row the snippet is rebuilt from the decoded body with the exact
// receive-time rule (mailapi.MakeSnippet); a row is written if its body OR its snippet
// changes, so previously body-only-backfilled rows now get their stale snippet fixed too.
//
// It is dry-run by default. Re-run with -apply to write; -apply first copies the DB file
// to "<db>.bak.<unix>" so the migration is reversible.
//
//	go run ./cmd/backfill-bodies -db mailanchor.db            # preview
//	go run ./cmd/backfill-bodies -db mailanchor.db -apply     # backup + rewrite
package main

import (
	"database/sql"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"time"

	_ "modernc.org/sqlite"

	"mailanchor/serverd/internal/imapx"
	"mailanchor/serverd/internal/mailapi"
)

func main() {
	dbPath := flag.String("db", "mailanchor.db", "path to the SQLite mail database")
	apply := flag.Bool("apply", false, "write changes (default: dry-run preview only)")
	flag.Parse()

	if err := run(*dbPath, *apply); err != nil {
		fmt.Fprintln(os.Stderr, "backfill-bodies:", err)
		os.Exit(1)
	}
}

func run(dbPath string, apply bool) error {
	if apply {
		bak := fmt.Sprintf("%s.bak.%d", dbPath, time.Now().Unix())
		if err := copyFile(dbPath, bak); err != nil {
			return fmt.Errorf("backup: %w", err)
		}
		fmt.Printf("backup written: %s\n", bak)
	} else {
		fmt.Println("DRY-RUN (no changes written) — re-run with -apply to commit")
	}

	dsn := fmt.Sprintf("file:%s?_pragma=busy_timeout(5000)", url.PathEscape(dbPath))
	conn, err := sql.Open("sqlite", dsn)
	if err != nil {
		return fmt.Errorf("open: %w", err)
	}
	defer conn.Close()
	conn.SetMaxOpenConns(1)
	if err := conn.Ping(); err != nil {
		return fmt.Errorf("ping %s: %w", dbPath, err)
	}

	rows, err := conn.Query(`SELECT mail_id, body_content, snippet FROM mail`)
	if err != nil {
		return fmt.Errorf("select: %w", err)
	}
	type change struct {
		id, newBody, newSnippet string
		bodyFixed, snipFixed    bool
	}
	var changes []change
	var total, bodyFixes, snipFixes int
	for rows.Next() {
		var id string
		var body, snip sql.NullString
		if err := rows.Scan(&id, &body, &snip); err != nil {
			rows.Close()
			return fmt.Errorf("scan: %w", err)
		}
		total++
		if !body.Valid {
			continue
		}
		// Re-decode the stored body (no-op for rows already repaired or never raw),
		// then rebuild the list snippet from that decoded body with the receive-time rule.
		decoded, bodyFixed := imapx.DecodeStoredBody(body.String)
		wantSnippet := mailapi.MakeSnippet(decoded)
		snipFixed := wantSnippet != snip.String
		if !bodyFixed && !snipFixed {
			continue
		}
		if bodyFixed {
			bodyFixes++
		}
		if snipFixed {
			snipFixes++
		}
		changes = append(changes, change{id, decoded, wantSnippet, bodyFixed, snipFixed})
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return fmt.Errorf("iterate: %w", err)
	}
	rows.Close()

	fmt.Printf("scanned %d rows; %d need re-writing (%d body, %d snippet)\n",
		total, len(changes), bodyFixes, snipFixes)
	for i, c := range changes {
		if i < 5 {
			fmt.Printf("  e.g. %s -> body=%s | snippet=%s\n", c.id, preview(c.newBody), preview(c.newSnippet))
		}
	}

	if !apply {
		return nil
	}
	if len(changes) == 0 {
		fmt.Println("nothing to write")
		return nil
	}

	tx, err := conn.Begin()
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	stmt, err := tx.Prepare(`UPDATE mail SET body_content = ?, snippet = ? WHERE mail_id = ?`)
	if err != nil {
		tx.Rollback()
		return fmt.Errorf("prepare: %w", err)
	}
	for _, c := range changes {
		if _, err := stmt.Exec(c.newBody, c.newSnippet, c.id); err != nil {
			stmt.Close()
			tx.Rollback()
			return fmt.Errorf("update %s: %w", c.id, err)
		}
	}
	stmt.Close()
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	fmt.Printf("updated %d rows\n", len(changes))
	return nil
}

func preview(s string) string {
	const max = 40
	r := []rune(s)
	cut := false
	if len(r) > max {
		r = r[:max]
		cut = true
	}
	out := make([]rune, 0, len(r))
	for _, c := range r {
		if c == '\n' || c == '\r' || c == '\t' {
			c = ' '
		}
		out = append(out, c)
	}
	s = string(out)
	if cut {
		s += "…"
	}
	return s
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}
