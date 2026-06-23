package mailapi

import (
	"database/sql"
	"errors"
	"strings"
	"time"

	"mailanchor/serverd/internal/idgen"
)

// ErrDuplicate is returned when a UNIQUE constraint (e.g. label name) is violated.
var ErrDuplicate = errors.New("duplicate")

type Store struct{ db *sql.DB }

func NewStore(db *sql.DB) *Store { return &Store{db: db} }

const tsLayout = "2006-01-02T15:04:05Z"

func isUnique(err error) bool {
	return err != nil && strings.Contains(err.Error(), "UNIQUE constraint failed")
}

// --- labels (M) ---

func (s *Store) ListLabels(userID string) ([]Label, error) {
	rows, err := s.db.Query(
		`SELECT label_id,name,type,color FROM label WHERE user_id=? ORDER BY type DESC, name ASC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Label{}
	for rows.Next() {
		var l Label
		var color sql.NullString
		if err := rows.Scan(&l.LabelID, &l.Name, &l.Type, &color); err != nil {
			return nil, err
		}
		if color.Valid {
			l.Color = &color.String
		}
		out = append(out, l)
	}
	return out, rows.Err()
}

func (s *Store) CreateLabel(userID, name string, color *string) (Label, error) {
	l := Label{LabelID: idgen.New(idgen.Label), Name: name, Type: "user", Color: color}
	_, err := s.db.Exec(
		`INSERT INTO label(label_id,user_id,name,type,color,created_at) VALUES(?,?,?, 'user', ?, ?)`,
		l.LabelID, userID, name, nullOf(color), nowUTC())
	if isUnique(err) {
		return Label{}, ErrDuplicate
	}
	if err != nil {
		return Label{}, err
	}
	return l, nil
}

// labelType returns the label's type, or sql.ErrNoRows if absent/not owned.
func (s *Store) labelType(userID, labelID string) (string, error) {
	var t string
	err := s.db.QueryRow(`SELECT type FROM label WHERE user_id=? AND label_id=?`, userID, labelID).Scan(&t)
	return t, err
}

func (s *Store) UpdateLabel(userID, labelID string, name, color *string) error {
	if name != nil {
		if _, err := s.db.Exec(`UPDATE label SET name=? WHERE user_id=? AND label_id=?`, *name, userID, labelID); isUnique(err) {
			return ErrDuplicate
		} else if err != nil {
			return err
		}
	}
	if color != nil {
		if _, err := s.db.Exec(`UPDATE label SET color=? WHERE user_id=? AND label_id=?`, nullOf(color), userID, labelID); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) DeleteLabel(userID, labelID string) error {
	_, err := s.db.Exec(`DELETE FROM label WHERE user_id=? AND label_id=?`, userID, labelID)
	return err
}

// --- settings (M) ---

type Display struct {
	SortOrder string `json:"sort_order"`
	Language  string `json:"language"`
	Density   string `json:"density"`
}

func (s *Store) GetDisplay(userID string) (Display, error) {
	var d Display
	err := s.db.QueryRow(`SELECT sort_order,language,density FROM user_settings WHERE user_id=?`, userID).
		Scan(&d.SortOrder, &d.Language, &d.Density)
	return d, err
}

func (s *Store) UpdateDisplay(userID string, d Display) error {
	_, err := s.db.Exec(`UPDATE user_settings SET sort_order=?,language=?,density=? WHERE user_id=?`,
		d.SortOrder, d.Language, d.Density, userID)
	return err
}

func (s *Store) GetSyncInterval(userID string) (*int, error) {
	var v sql.NullInt64
	err := s.db.QueryRow(`SELECT sync_interval_min FROM user_settings WHERE user_id=?`, userID).Scan(&v)
	if err != nil {
		return nil, err
	}
	if !v.Valid {
		return nil, nil
	}
	iv := int(v.Int64)
	return &iv, nil
}

func (s *Store) UpdateSyncInterval(userID string, interval *int) error {
	_, err := s.db.Exec(`UPDATE user_settings SET sync_interval_min=? WHERE user_id=?`, nullIntOf(interval), userID)
	return err
}

// --- mail read-path (C) ---

type listFilter struct {
	Label  string
	Q      string
	Unread bool
	Limit  int
	Cursor cursor
}

func (s *Store) ListMails(userID string, f listFilter) ([]MailSummary, bool, error) {
	var (
		args  []any
		where strings.Builder
	)
	where.WriteString(`WHERE m.user_id=?`)
	args = append(args, userID)

	if f.Label != "" {
		where.WriteString(` AND EXISTS (SELECT 1 FROM mail_label ml WHERE ml.mail_id=m.mail_id AND ml.label_id=?)`)
		args = append(args, f.Label)
	}
	if f.Unread {
		where.WriteString(` AND m.is_read=0`)
	}
	if f.Q != "" {
		like := "%" + escapeLike(f.Q) + "%"
		where.WriteString(` AND (m.subject LIKE ? ESCAPE '\' OR m.snippet LIKE ? ESCAPE '\' OR m.from_addr LIKE ? ESCAPE '\')`)
		args = append(args, like, like, like)
	}
	if f.Cursor.MailID != "" {
		// keyset: (received_at, mail_id) < (c.r, c.m)
		where.WriteString(` AND (m.received_at < ? OR (m.received_at = ? AND m.mail_id < ?))`)
		args = append(args, f.Cursor.ReceivedAt, f.Cursor.ReceivedAt, f.Cursor.MailID)
	}

	q := `SELECT m.mail_id,m.thread_id,m.from_addr,m.subject,m.snippet,m.received_at,m.is_read,m.has_attachment
	      FROM mail m ` + where.String() +
		` ORDER BY m.received_at DESC, m.mail_id DESC LIMIT ?`
	args = append(args, f.Limit+1) // +1 to detect has_more

	rows, err := s.db.Query(q, args...)
	if err != nil {
		return nil, false, err
	}
	defer rows.Close()

	var page []MailSummary
	ids := []string{}
	for rows.Next() {
		var (
			m        MailSummary
			fromJSON string
			isRead   int
			hasAtt   int
		)
		if err := rows.Scan(&m.MailID, &m.ThreadID, &fromJSON, &m.Subject, &m.Snippet, &m.ReceivedAt, &isRead, &hasAtt); err != nil {
			return nil, false, err
		}
		m.From = unmarshalAddr(fromJSON)
		m.IsRead = isRead == 1
		m.HasAttachment = hasAtt == 1
		m.Labels = []string{}
		page = append(page, m)
		ids = append(ids, m.MailID)
	}
	if err := rows.Err(); err != nil {
		return nil, false, err
	}

	hasMore := len(page) > f.Limit
	if hasMore {
		page = page[:f.Limit]
		ids = ids[:f.Limit]
	}
	if err := s.attachLabels(page, ids); err != nil {
		return nil, false, err
	}
	return page, hasMore, nil
}

func (s *Store) attachLabels(page []MailSummary, ids []string) error {
	if len(ids) == 0 {
		return nil
	}
	idx := make(map[string]int, len(page))
	for i := range page {
		idx[page[i].MailID] = i
	}
	ph := strings.Repeat("?,", len(ids))
	ph = ph[:len(ph)-1]
	args := make([]any, len(ids))
	for i, id := range ids {
		args[i] = id
	}
	rows, err := s.db.Query(`SELECT mail_id,label_id FROM mail_label WHERE mail_id IN (`+ph+`)`, args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var mailID, labelID string
		if err := rows.Scan(&mailID, &labelID); err != nil {
			return err
		}
		if i, ok := idx[mailID]; ok {
			page[i].Labels = append(page[i].Labels, labelID)
		}
	}
	return rows.Err()
}

func (s *Store) GetMailDetail(userID, mailID string) (MailDetail, error) {
	var (
		d        MailDetail
		fromJSON string
		toJSON   string
		ccJSON   string
		bodyFmt  string
		bodyCont sql.NullString
		isRead   int
	)
	err := s.db.QueryRow(
		`SELECT mail_id,thread_id,from_addr,to_addrs,cc_addrs,subject,received_at,is_read,body_format,body_content
		 FROM mail WHERE user_id=? AND mail_id=?`, userID, mailID).
		Scan(&d.MailID, &d.ThreadID, &fromJSON, &toJSON, &ccJSON, &d.Subject, &d.ReceivedAt, &isRead, &bodyFmt, &bodyCont)
	if err != nil {
		return MailDetail{}, err
	}
	d.From = unmarshalAddr(fromJSON)
	d.To = unmarshalAddrs(toJSON)
	d.CC = unmarshalAddrs(ccJSON)
	d.IsRead = isRead == 1
	d.Body = Body{Format: bodyFmt, Content: bodyCont.String}
	d.Attachments = []Attachment{}
	d.Labels = []string{}

	arows, err := s.db.Query(
		`SELECT attachment_id,filename,size_bytes,content_type FROM attachment WHERE mail_id=?`, mailID)
	if err != nil {
		return MailDetail{}, err
	}
	defer arows.Close()
	for arows.Next() {
		var a Attachment
		if err := arows.Scan(&a.AttachmentID, &a.Filename, &a.SizeBytes, &a.ContentType); err != nil {
			return MailDetail{}, err
		}
		d.Attachments = append(d.Attachments, a)
	}
	lrows, err := s.db.Query(`SELECT label_id FROM mail_label WHERE mail_id=?`, mailID)
	if err != nil {
		return MailDetail{}, err
	}
	defer lrows.Close()
	for lrows.Next() {
		var lid string
		if err := lrows.Scan(&lid); err != nil {
			return MailDetail{}, err
		}
		d.Labels = append(d.Labels, lid)
	}
	return d, nil
}

// PatchMail applies is_read and label add/remove in one transaction (L0012 §2.5).
// Returns ErrLabelMissing if a labels_add target is not owned.
var ErrLabelMissing = errors.New("label missing")

func (s *Store) PatchMail(userID, mailID string, isRead *bool, add, remove []string) error {
	// ownership check
	var owned int
	if err := s.db.QueryRow(`SELECT 1 FROM mail WHERE user_id=? AND mail_id=?`, userID, mailID).Scan(&owned); err != nil {
		return err // sql.ErrNoRows -> MAIL_NOT_FOUND
	}
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck

	if isRead != nil {
		v := 0
		if *isRead {
			v = 1
		}
		if _, err := tx.Exec(`UPDATE mail SET is_read=? WHERE mail_id=?`, v, mailID); err != nil {
			return err
		}
	}
	for _, lid := range add {
		var t string
		if err := tx.QueryRow(`SELECT type FROM label WHERE user_id=? AND label_id=?`, userID, lid).Scan(&t); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return ErrLabelMissing
			}
			return err
		}
		if _, err := tx.Exec(`INSERT OR IGNORE INTO mail_label(mail_id,label_id) VALUES(?,?)`, mailID, lid); err != nil {
			return err
		}
	}
	for _, lid := range remove {
		if _, err := tx.Exec(`DELETE FROM mail_label WHERE mail_id=? AND label_id=?`, mailID, lid); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) CurrentLabels(mailID string) ([]string, error) {
	rows, err := s.db.Query(`SELECT label_id FROM mail_label WHERE mail_id=?`, mailID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var lid string
		if err := rows.Scan(&lid); err != nil {
			return nil, err
		}
		out = append(out, lid)
	}
	return out, rows.Err()
}

// SeedMail inserts an inbound mail. Represents what sync(F) would persist; used by
// tests and dev (no HTTP write-path is implemented in this phase).
func (s *Store) SeedMail(userID, accountID string, m MailSummary, body string, to []Address) (string, error) {
	id := idgen.New(idgen.Mail)
	hasAtt := 0
	if m.HasAttachment {
		hasAtt = 1
	}
	isRead := 0
	if m.IsRead {
		isRead = 1
	}
	from, _ := marshalOne(m.From)
	_, err := s.db.Exec(
		`INSERT INTO mail(mail_id,user_id,account_id,thread_id,from_addr,to_addrs,cc_addrs,subject,snippet,
		   body_format,body_content,received_at,is_read,has_attachment,direction)
		 VALUES(?,?,?,?,?,?,?,?,?, 'text',?,?,?,?, 'inbound')`,
		id, userID, accountID, m.ThreadID, from, marshalAddrs(to), "[]", m.Subject, m.Snippet,
		body, m.ReceivedAt, isRead, hasAtt)
	return id, err
}

func nowUTC() string { return time.Now().UTC().Truncate(time.Second).Format(tsLayout) }

func nullOf(s *string) any {
	if s == nil {
		return nil
	}
	return *s
}

func nullIntOf(i *int) any {
	if i == nil {
		return nil
	}
	return *i
}

func escapeLike(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return r.Replace(s)
}
