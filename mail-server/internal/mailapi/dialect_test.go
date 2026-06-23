package mailapi

import (
	"errors"
	"testing"
)

// insertIgnoreInto must emit the correct dialect prefix so the mail_label idempotent
// inserts (store.go / sync.go) work on both SQLite and MySQL (stage 1).
func TestInsertIgnoreIntoDialect(t *testing.T) {
	orig := activeDialect
	defer func() { activeDialect = orig }()

	activeDialect = dialectSQLite
	if got := insertIgnoreInto("mail_label"); got != "INSERT OR IGNORE INTO mail_label" {
		t.Fatalf("sqlite: %q", got)
	}
	activeDialect = dialectMySQL
	if got := insertIgnoreInto("mail_label"); got != "INSERT IGNORE INTO mail_label" {
		t.Fatalf("mysql: %q", got)
	}
}

// isUnique must recognise the duplicate-key error of both dialects so 409 LABEL_DUPLICATE
// (and the account/uniqueness paths) keep working after a MySQL switch.
func TestIsUniqueAcrossDialects(t *testing.T) {
	if isUnique(nil) {
		t.Fatal("nil err is not a unique violation")
	}
	if !isUnique(errors.New("UNIQUE constraint failed: label.user_id, label.name")) {
		t.Fatal("sqlite unique error not detected")
	}
	if !isUnique(errors.New("Error 1062 (23000): Duplicate entry 'u1-Work' for key 'uq_label_user_name'")) {
		t.Fatal("mysql duplicate error not detected")
	}
	if isUnique(errors.New("some unrelated error")) {
		t.Fatal("unrelated error must not be a unique violation")
	}
}
