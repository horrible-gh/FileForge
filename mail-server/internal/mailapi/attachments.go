package mailapi

import (
	"database/sql"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"mailanchor/serverd/internal/apperr"
	"mailanchor/serverd/internal/httpx"
	"mailanchor/serverd/internal/idgen"
	"mailanchor/serverd/internal/storage"
)

// attachmentsMaxPerMail — L0012 §1.
const attachmentsMaxPerMail = 20

// uploadMaxBytes caps a single attachment upload (operational;容量 정책 DEFERRED — L0012).
const uploadMaxBytes = 25 << 20 // 25 MiB

// InsertAttachment records attachment metadata bound to a draft (DB0008 §2.7,
// 불변식 5: exactly one of mail_id/draft_id). Bytes already live in Blob at ref.
// Enforces attachments_max_per_mail per draft.
func (s *Store) InsertAttachment(userID, draftID, filename, contentType, ref string, size int64) (Attachment, error) {
	var owned int
	if err := s.db.QueryRow(`SELECT 1 FROM draft WHERE user_id=? AND draft_id=?`, userID, draftID).Scan(&owned); err != nil {
		return Attachment{}, err // sql.ErrNoRows -> draft not found
	}
	var cnt int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM attachment WHERE draft_id=?`, draftID).Scan(&cnt); err != nil {
		return Attachment{}, err
	}
	if cnt >= attachmentsMaxPerMail {
		return Attachment{}, ErrTooManyAttachments
	}
	a := Attachment{AttachmentID: idgen.New(idgen.Attachment), Filename: filename, SizeBytes: size, ContentType: contentType}
	_, err := s.db.Exec(
		`INSERT INTO attachment(attachment_id,mail_id,draft_id,filename,size_bytes,content_type,storage_ref,created_at)
		 VALUES(?, NULL, ?, ?, ?, ?, ?, ?)`,
		a.AttachmentID, draftID, filename, size, contentType, ref, nowUTC())
	if err != nil {
		return Attachment{}, err
	}
	return a, nil
}

// ErrTooManyAttachments — per-draft attachment count exceeds attachments_max_per_mail.
var ErrTooManyAttachments = errors.New("too many attachments")

// attachmentBytes returns the filename/content-type/storage_ref of a user-owned
// attachment (bound to either a mail or a draft they own).
func (s *Store) attachmentBytes(userID, attachmentID string) (filename, contentType, ref string, err error) {
	err = s.db.QueryRow(
		`SELECT a.filename,a.content_type,a.storage_ref FROM attachment a
		 LEFT JOIN mail m  ON a.mail_id=m.mail_id
		 LEFT JOIN draft d ON a.draft_id=d.draft_id
		 WHERE a.attachment_id=? AND (m.user_id=? OR d.user_id=?)`,
		attachmentID, userID, userID).Scan(&filename, &contentType, &ref)
	return
}

// --- handlers ---

// UploadAttachment implements POST /attachments (P0007 §7.11, multipart/form-data).
// The attachment binds to a draft (field draft_id) so the DB0008 불변식 5 exclusive
// ownership CHECK holds at upload time; send re-attributes it to the mail (L0012 §2.4).
func (h *Handlers) UploadAttachment(w http.ResponseWriter, r *http.Request) {
	if h.deps.Blob == nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	// Cap the TOTAL request body (NR0011 S4): ParseMultipartForm's argument only bounds the
	// in-memory portion, not the overall upload, so without this a large/streamed body could
	// exhaust memory/disk. Allow one attachment + modest multipart overhead.
	r.Body = http.MaxBytesReader(w, r.Body, uploadMaxBytes+(1<<20))
	if err := r.ParseMultipartForm(uploadMaxBytes); err != nil {
		if isMaxBytesError(err) {
			httpx.Error(w, apperr.PayloadTooLarge)
			return
		}
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"reason": "multipart parse failed"}))
		return
	}
	draftID := r.FormValue("draft_id")
	if draftID == "" {
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "draft_id"}))
		return
	}
	file, hdr, err := r.FormFile("file")
	if err != nil {
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "file"}))
		return
	}
	defer file.Close()

	contentType := hdr.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	// Read one byte past the limit so an over-limit file is REJECTED (413), not silently
	// truncated to uploadMaxBytes and stored as a corrupt partial (NR0011 S4).
	ref, size, err := h.deps.Blob.Put(io.LimitReader(file, uploadMaxBytes+1))
	if err != nil {
		if isMaxBytesError(err) { // total request body exceeded the cap mid-copy
			httpx.Error(w, apperr.PayloadTooLarge)
			return
		}
		httpx.Error(w, apperr.Internal)
		return
	}
	if size > uploadMaxBytes {
		_ = h.deps.Blob.Delete(ref)
		httpx.Error(w, apperr.PayloadTooLarge)
		return
	}
	a, err := h.store.InsertAttachment(uid(r), draftID, hdr.Filename, contentType, ref, size)
	if errors.Is(err, sql.ErrNoRows) {
		_ = h.deps.Blob.Delete(ref) // orphan cleanup: draft not found
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "draft_id", "reason": "draft not found"}))
		return
	}
	if errors.Is(err, ErrTooManyAttachments) {
		_ = h.deps.Blob.Delete(ref)
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"reason": "attachment limit exceeded"}))
		return
	}
	if err != nil {
		_ = h.deps.Blob.Delete(ref)
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.OK(w, http.StatusCreated, a)
}

// DownloadAttachment implements GET /attachments/{id} (P0007 §7.12): raw bytes with
// the attachment's real content type and a download disposition.
func (h *Handlers) DownloadAttachment(w http.ResponseWriter, r *http.Request) {
	if h.deps.Blob == nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	filename, contentType, ref, err := h.store.attachmentBytes(uid(r), chi.URLParam(r, "id"))
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, apperr.AttachmentNotFound)
		return
	}
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	rc, err := h.deps.Blob.Open(ref)
	if errors.Is(err, storage.ErrNotFound) {
		httpx.Error(w, apperr.AttachmentNotFound)
		return
	}
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	defer rc.Close()
	w.Header().Set("Content-Type", contentType)
	// nosniff so a browser cannot MIME-sniff a client-declared Content-Type into an
	// executable type (NR0011 S5); combined with the attachment disposition below.
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Content-Disposition", "attachment; filename=\""+sanitizeFilename(filename)+"\"")
	w.WriteHeader(http.StatusOK)
	_, _ = io.Copy(w, rc)
}

// isMaxBytesError reports whether err is the over-limit signal from http.MaxBytesReader.
func isMaxBytesError(err error) bool {
	var mbe *http.MaxBytesError
	if errors.As(err, &mbe) {
		return true
	}
	return err != nil && strings.Contains(err.Error(), "request body too large")
}

// sanitizeFilename strips quotes/control chars from a Content-Disposition filename.
func sanitizeFilename(name string) string {
	out := make([]rune, 0, len(name))
	for _, c := range name {
		if c == '"' || c == '\\' || c < 0x20 {
			continue
		}
		out = append(out, c)
	}
	if len(out) == 0 {
		return "download"
	}
	return string(out)
}
