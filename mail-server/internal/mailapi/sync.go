package mailapi

import (
	"database/sql"
	"errors"
	"net/http"
	"time"

	"mailanchor/serverd/internal/apperr"
	"mailanchor/serverd/internal/httpx"
	"mailanchor/serverd/internal/idgen"
)

// L0013 §1 sync parameters.
const (
	syncBatchSize      = 200
	syncMaxPages       = 25
	oauthRefreshMargin = 300 // seconds
	// syncStaleTTL: a 'syncing' row not touched within this window is assumed abandoned
	// (the worker crashed/panicked before releasing it) and is reclaimable (NR0011 B2).
	syncStaleTTL = 10 * time.Minute
)

// errReauth signals an external auth failure -> account reauth_required (L0013 §2.2).
var errReauth = errors.New("reauth_required")

// SyncStatus — wire shape (P0007 §3.7).
type SyncStatusDTO struct {
	State        string  `json:"state"`
	LastSyncedAt *string `json:"last_synced_at"`
	Pending      bool    `json:"pending"`
}

type syncRow struct {
	State        string
	LastSyncedAt sql.NullString
	SyncCursor   sql.NullString
	LastError    sql.NullString
}

func (s *Store) syncStateOf(accountID string) (syncRow, error) {
	var r syncRow
	err := s.db.QueryRow(
		`SELECT state,last_synced_at,sync_cursor,last_error FROM sync_state WHERE account_id=?`, accountID).
		Scan(&r.State, &r.LastSyncedAt, &r.SyncCursor, &r.LastError)
	return r, err
}

// acquireSyncLock atomically flips idle/error -> syncing and stamps updated_at. Returns
// false if the row is already syncing (idempotent — L0013 §2.1/§2.2) or absent. A
// 'syncing' row whose updated_at is older than staleBefore is reclaimed (NR0011 B2:
// abandoned lock after a crash/panic), so sync can never wedge permanently.
func (s *Store) acquireSyncLock(accountID, now, staleBefore string) (bool, error) {
	res, err := s.db.Exec(
		`UPDATE sync_state SET state='syncing', last_error=NULL, updated_at=?
		 WHERE account_id=? AND (state!='syncing' OR updated_at IS NULL OR updated_at < ?)`,
		now, accountID, staleBefore)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

func (s *Store) finishSync(accountID, cursor, now string) error {
	_, err := s.db.Exec(
		`UPDATE sync_state SET state='idle', last_synced_at=?, sync_cursor=?, last_error=NULL, updated_at=? WHERE account_id=?`,
		now, nullStr(cursor), now, accountID)
	return err
}

func (s *Store) failSync(accountID, reason, now string) error {
	_, err := s.db.Exec(
		`UPDATE sync_state SET state='error', last_error=?, updated_at=? WHERE account_id=?`,
		reason, now, accountID)
	return err
}

func (s *Store) setAccountStatus(accountID, status string) error {
	_, err := s.db.Exec(`UPDATE mail_account SET status=? WHERE account_id=?`, status, accountID)
	return err
}

// --- merge (L0013 §2.3) ---

// applyChange merges one external change into local mail in its own transaction
// (find_by_external_ref -> insert / merge / delete with field-level authority §2.3.1).
func (s *Store) applyChange(acc primaryAccountSync, ch ExternalChange) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck

	var existing string
	err = tx.QueryRow(`SELECT mail_id FROM mail WHERE account_id=? AND external_ref=?`,
		acc.AccountID, ch.ExternalID).Scan(&existing)
	found := err == nil
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}

	if ch.Kind == ChangeDeleted {
		if found {
			if _, err := tx.Exec(`DELETE FROM mail WHERE mail_id=?`, existing); err != nil {
				return err
			}
		}
		return tx.Commit()
	}

	if !found {
		mailID := idgen.New(idgen.Mail)
		fromJSON, _ := marshalOne(ch.From)
		hasAtt := 0
		if len(ch.Attachments) > 0 {
			hasAtt = 1
		}
		isRead := 0
		if ch.IsRead {
			isRead = 1
		}
		snippet := ch.Snippet
		if snippet == "" {
			snippet = makeSnippet(ch.Body.Content)
		}
		threadID := ch.ThreadKey
		if threadID == "" {
			threadID = idgen.New(idgen.Thread)
		}
		if _, err := tx.Exec(
			`INSERT INTO mail(mail_id,user_id,account_id,thread_id,from_addr,to_addrs,cc_addrs,subject,snippet,
			   body_format,body_content,received_at,is_read,has_attachment,direction,external_ref)
			 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'inbound', ?)`,
			mailID, acc.UserID, acc.AccountID, threadID, fromJSON, marshalAddrs(ch.To), marshalAddrs(ch.CC),
			ch.Subject, snippet, bodyFormat(ch.Body), ch.Body.Content, ch.ReceivedAt, isRead, hasAtt, ch.ExternalID); err != nil {
			return err
		}
		if err := replaceLabelsTx(tx, acc.UserID, mailID, ch.Labels); err != nil {
			return err
		}
		if err := replaceAttachmentsTx(tx, mailID, ch.Attachments); err != nil {
			return err
		}
		if err := recomputeHasAttachmentTx(tx, mailID); err != nil {
			return err
		}
		return tx.Commit()
	}

	// merge_existing — field-level authority (§2.3.1).
	// is_read: monotonic OR (once read stays read). Others: external authority.
	var localRead int
	if err := tx.QueryRow(`SELECT is_read FROM mail WHERE mail_id=?`, existing).Scan(&localRead); err != nil {
		return err
	}
	newRead := localRead
	if ch.IsRead {
		newRead = 1
	}
	if _, err := tx.Exec(
		`UPDATE mail SET subject=?, body_format=?, body_content=?, snippet=?, received_at=?, is_read=? WHERE mail_id=?`,
		ch.Subject, bodyFormat(ch.Body), ch.Body.Content,
		func() string {
			if ch.Snippet != "" {
				return ch.Snippet
			}
			return makeSnippet(ch.Body.Content)
		}(), ch.ReceivedAt, newRead, existing); err != nil {
		return err
	}
	if ch.LabelsPartial {
		// non-destructive: add advertised labels, keep the rest (NR0011 B3)
		if err := addLabelsTx(tx, acc.UserID, existing, ch.Labels); err != nil {
			return err
		}
	} else if err := replaceLabelsTx(tx, acc.UserID, existing, ch.Labels); err != nil { // external authority
		return err
	}
	if err := replaceAttachmentsTx(tx, existing, ch.Attachments); err != nil {
		return err
	}
	if err := recomputeHasAttachmentTx(tx, existing); err != nil {
		return err
	}
	return tx.Commit()
}

// replaceLabelsTx sets a mail's labels to exactly the external set (external authority):
// each name is resolved to a label_id (system labels reuse the seeded row; others are
// created as user labels), then mail_label is rewritten.
func replaceLabelsTx(tx *sql.Tx, userID, mailID string, names []string) error {
	if _, err := tx.Exec(`DELETE FROM mail_label WHERE mail_id=?`, mailID); err != nil {
		return err
	}
	for _, name := range names {
		lid, err := upsertLabelTx(tx, userID, name)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(insertIgnoreInto("mail_label")+`(mail_id,label_id) VALUES(?,?)`, mailID, lid); err != nil {
			return err
		}
	}
	return nil
}

// addLabelsTx adds the given labels to a mail without removing existing ones (NR0011 B3
// non-destructive merge for sources that report a partial label view). INSERT OR IGNORE
// keeps it idempotent.
func addLabelsTx(tx *sql.Tx, userID, mailID string, names []string) error {
	for _, name := range names {
		lid, err := upsertLabelTx(tx, userID, name)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(insertIgnoreInto("mail_label")+`(mail_id,label_id) VALUES(?,?)`, mailID, lid); err != nil {
			return err
		}
	}
	return nil
}

var systemLabelNames = map[string]bool{"inbox": true, "sent": true, "draft": true}

func upsertLabelTx(tx *sql.Tx, userID, name string) (string, error) {
	if systemLabelNames[name] {
		return name + "_" + userID, nil // seeded at CreateUser
	}
	var lid string
	err := tx.QueryRow(`SELECT label_id FROM label WHERE user_id=? AND name=?`, userID, name).Scan(&lid)
	if err == nil {
		return lid, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return "", err
	}
	lid = idgen.New(idgen.Label)
	if _, err := tx.Exec(
		`INSERT INTO label(label_id,user_id,name,type,color,created_at) VALUES(?,?,?, 'user', NULL, ?)`,
		lid, userID, name, nowUTC()); err != nil {
		return "", err
	}
	return lid, nil
}

// replaceAttachmentsTx rewrites a mail's attachment metadata from the external set.
func replaceAttachmentsTx(tx *sql.Tx, mailID string, atts []ExternalAttachment) error {
	if _, err := tx.Exec(`DELETE FROM attachment WHERE mail_id=?`, mailID); err != nil {
		return err
	}
	for _, a := range atts {
		ref := a.StorageRef
		if ref == "" {
			ref = "pending:" + idgen.New("ref_") // deferred byte download (L0013 DEFERRED)
		}
		if _, err := tx.Exec(
			`INSERT INTO attachment(attachment_id,mail_id,draft_id,filename,size_bytes,content_type,storage_ref,created_at)
			 VALUES(?, ?, NULL, ?, ?, ?, ?, ?)`,
			idgen.New(idgen.Attachment), mailID, a.Filename, a.SizeBytes, a.ContentType, ref, nowUTC()); err != nil {
			return err
		}
	}
	return nil
}

// primaryAccountSync is the minimal account view the merge needs.
type primaryAccountSync struct {
	AccountID string
	UserID    string
	Email     string
	Provider  string
	OAuthRef  string
}

// connectedAccountsForSync returns the user's connected accounts (sync targets).
func (s *Store) connectedAccountsForSync(userID string) ([]primaryAccountSync, error) {
	rows, err := s.db.Query(
		`SELECT account_id,user_id,email,provider,COALESCE(oauth_ref,'')
		 FROM mail_account WHERE user_id=? AND status='connected' ORDER BY connected_at ASC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []primaryAccountSync{}
	for rows.Next() {
		var a primaryAccountSync
		if err := rows.Scan(&a.AccountID, &a.UserID, &a.Email, &a.Provider, &a.OAuthRef); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// runSync executes one sync session for an account (L0013 §2.2). Runs inline; the
// background scheduler/parallelism is operational DEFERRED (L0013 DEFERRED). Returns
// the number of changes applied.
func (h *Handlers) runSync(acc primaryAccountSync) (int, error) {
	nowT := h.deps.now().UTC().Truncate(time.Second)
	now := nowT.Format(tsLayout)
	staleBefore := nowT.Add(-syncStaleTTL).Format(tsLayout)

	got, err := h.store.acquireSyncLock(acc.AccountID, now, staleBefore)
	if err != nil {
		return 0, err
	}
	if !got {
		return 0, nil // already syncing (and not stale) -> idempotent no-op
	}

	// Panic safety (NR0011 B2): runSync owns every sync_state write so the lock is always
	// settled. doSyncLocked never touches sync_state; if it (or an adapter it calls)
	// panics, this defer flips the row out of 'syncing' before the panic propagates,
	// instead of stranding the account in a permanent syncing state.
	settled := false
	defer func() {
		if !settled {
			_ = h.store.failSync(acc.AccountID, "interrupted", h.now())
		}
	}()

	applied, cursor, reauth, serr := h.doSyncLocked(acc)
	settled = true
	if reauth {
		_ = h.store.setAccountStatus(acc.AccountID, "reauth_required")
		_ = h.store.failSync(acc.AccountID, "reauth_required", h.now())
		return applied, errReauth
	}
	if serr != nil {
		_ = h.store.failSync(acc.AccountID, serr.Error(), h.now())
		return applied, serr
	}
	if ferr := h.store.finishSync(acc.AccountID, cursor, h.now()); ferr != nil {
		return applied, ferr
	}
	return applied, nil
}

// doSyncLocked runs the fetch/merge loop assuming the sync lock is held. It returns the
// applied count, final cursor, whether the failure requires reauth, and any error. It
// deliberately performs NO sync_state writes — runSync settles the lock so a panic here
// cannot strand it (NR0011 B2).
func (h *Handlers) doSyncLocked(acc primaryAccountSync) (applied int, cursor string, reauth bool, err error) {
	if oerr := h.ensureOAuthFresh(acc); oerr != nil {
		if errors.Is(oerr, errReauth) {
			return 0, "", true, oerr
		}
		return 0, "", false, oerr
	}
	if h.deps.Source == nil {
		return 0, "", false, errors.New("no change source")
	}

	st, _ := h.store.syncStateOf(acc.AccountID)
	cursor = st.SyncCursor.String
	ext := ExternalAccount{AccountID: acc.AccountID, UserID: acc.UserID, Email: acc.Email,
		Provider: acc.Provider, OAuthRef: acc.OAuthRef}

	pages := 0
	for {
		var batch ChangeBatch
		ferr := h.deps.sendRetry().Do(func() error {
			b, e := h.deps.Source.FetchChanges(ext, cursor, syncBatchSize)
			if e != nil {
				return e
			}
			batch = b
			return nil
		}, h.sleep)
		if ferr != nil {
			return applied, cursor, false, ferr
		}
		for _, ch := range batch.Items {
			if aerr := h.store.applyChange(acc, ch); aerr != nil {
				return applied, cursor, false, aerr
			}
			applied++
		}
		cursor = batch.NextCursor
		pages++
		if !batch.HasMore || pages >= syncMaxPages {
			break
		}
	}
	return applied, cursor, false, nil
}

// ensureOAuthFresh pre-refreshes the OAuth access token within the margin (L0013 §2.5).
// No-ops for password/IMAP accounts or when OAuth/Secrets ports are absent.
func (h *Handlers) ensureOAuthFresh(acc primaryAccountSync) error {
	if acc.OAuthRef == "" || h.deps.Secrets == nil || h.deps.OAuth == nil {
		return nil
	}
	cred, ok := h.deps.Secrets.Get(acc.OAuthRef)
	if !ok {
		return nil
	}
	if cred.Expiry.IsZero() {
		return nil
	}
	remaining := cred.Expiry.Sub(h.deps.now()).Seconds()
	if remaining > oauthRefreshMargin {
		return nil
	}
	refreshed, err := h.deps.OAuth.Refresh(acc.Provider, cred.RefreshToken)
	if err != nil {
		// Only a permanent invalid_grant forces reauth; transient failures (network/5xx)
		// surface as a retriable sync error so a token-endpoint blip doesn't disconnect a
		// healthy account (NR0011 B7).
		if errors.Is(err, ErrOAuthInvalidGrant) {
			return errReauth
		}
		return err
	}
	h.deps.Secrets.Put(acc.OAuthRef, refreshed)
	return nil
}

// --- handlers ---

// SyncStatus implements GET /sync/status (P0007 §7.15). Reports the primary account's
// sync_state (no account -> idle/empty).
func (h *Handlers) SyncStatus(w http.ResponseWriter, r *http.Request) {
	accts, err := h.store.connectedAccountsForSync(uid(r))
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	if len(accts) == 0 {
		httpx.OK(w, http.StatusOK, SyncStatusDTO{State: "idle", Pending: false})
		return
	}
	st, err := h.store.syncStateOf(accts[0].AccountID)
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	dto := SyncStatusDTO{State: st.State, Pending: st.State == "syncing"}
	if st.LastSyncedAt.Valid {
		dto.LastSyncedAt = &st.LastSyncedAt.String
	}
	httpx.OK(w, http.StatusOK, dto)
}

// TriggerSync implements POST /sync (P0007 §7.15): manual trigger across the user's
// connected accounts. 202 with started_at; the resulting state reflects completion
// since sync runs inline (background worker DEFERRED).
func (h *Handlers) TriggerSync(w http.ResponseWriter, r *http.Request) {
	userID := uid(r)
	accts, err := h.store.connectedAccountsForSync(userID)
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	if len(accts) == 0 {
		httpx.Error(w, apperr.UpstreamUnavailable.WithDetails(map[string]any{"reason": "no connected account"}))
		return
	}
	if h.deps.Source == nil {
		httpx.Error(w, apperr.UpstreamUnavailable.WithDetails(map[string]any{"reason": "sync source not configured"}))
		return
	}

	started := h.now()
	total := 0
	reauth := false
	for _, acc := range accts {
		n, err := h.runSync(acc)
		total += n
		if errors.Is(err, errReauth) {
			reauth = true
		}
	}
	// report the primary account's resulting state
	st, _ := h.store.syncStateOf(accts[0].AccountID)
	resp := map[string]any{"state": st.State, "started_at": started, "applied": total}
	if reauth {
		resp["reauth_required"] = true
	}
	httpx.OK(w, http.StatusAccepted, resp)
}
