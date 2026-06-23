package mailapi

import (
	"errors"
	"time"

	"mailanchor/serverd/internal/retry"
	"mailanchor/serverd/internal/storage"
)

// ErrOAuthInvalidGrant signals an OAuth refresh failure that is permanent (the refresh
// token is revoked/expired, RFC 6749 "invalid_grant") and therefore warrants forcing
// account reauth. Transient failures (network / 5xx) wrap a different error so sync can
// retry instead of nuking the connection (NR0011 B7). The oauthx adapter returns this.
var ErrOAuthInvalidGrant = errors.New("oauth invalid_grant")

// This file defines the external-service port boundary (Phase 2). The mail
// transaction logic (send L0012 §2.4, sync merge L0013 §2.3) is written against
// these interfaces so it is fully testable with fakes; the concrete SMTP/IMAP/OAuth
// wire adapters plug in behind them. Provider-specific change-fetch differences are
// L0013 DEFERRED ("외부 제공자별 변경 페치 API 차이").

// OutgoingMail is the payload handed to the external Sender (SMTP).
type OutgoingMail struct {
	From    Address
	To      []Address
	CC      []Address
	BCC     []Address
	Subject string
	Body    Body
	// Attachments carried by value so the Sender does not need DB access.
	Attachments []OutgoingAttachment
}

// OutgoingAttachment is one attachment's bytes + metadata for the Sender.
type OutgoingAttachment struct {
	Filename    string
	ContentType string
	StorageRef  string // resolved by the handler via Blob.Open when building the MIME body
}

// Sender delivers a composed mail through the external provider (SMTP). A non-nil
// error is treated as transient unless wrapped with retry.Permanent.
type Sender interface {
	Send(account ExternalAccount, m OutgoingMail) error
}

// ExternalAccount carries the per-account connection facts the adapters need.
// Secrets are never stored in SQL (DB0008 §2.3 oauth_ref -> SecretStore).
type ExternalAccount struct {
	AccountID string
	UserID    string
	Email     string
	Provider  string // gmail|outlook|imap
	OAuthRef  string // key into SecretStore (may be empty for password/IMAP setups)
}

// ChangeKind classifies an external change (L0013 §2.3).
type ChangeKind string

const (
	ChangeUpsert  ChangeKind = "upsert"
	ChangeDeleted ChangeKind = "deleted"
)

// ExternalChange is one provider-side change to merge into local mail (L0013 §2.3).
type ExternalChange struct {
	Kind       ChangeKind
	ExternalID string // provider message id -> mail.external_ref (mig 013)
	ThreadKey  string // provider thread grouping key
	From       Address
	To         []Address
	CC         []Address
	Subject    string
	Body       Body
	Snippet    string
	ReceivedAt string // ISO-8601 UTC
	IsRead     bool
	Labels     []string // external label names -> local label upsert
	// LabelsPartial marks Labels as an INCOMPLETE view (the source only knows some of the
	// message's labels — e.g. an INBOX-only IMAP fetch that cannot see sent/draft/user
	// labels). When true the merge UNIONs labels (non-destructive) instead of replacing,
	// so a re-sync does not wipe labels the source never advertised (NR0011 B3). When
	// false (default) Labels are authoritative and fully replace the local set.
	LabelsPartial bool
	Attachments   []ExternalAttachment
}

// ExternalAttachment is attachment metadata observed during sync.
type ExternalAttachment struct {
	Filename    string
	ContentType string
	SizeBytes   int64
	StorageRef  string // provider-fetched bytes already persisted to Blob, or deferred ref
}

// ChangeBatch is one page of incremental changes from the provider.
type ChangeBatch struct {
	Items      []ExternalChange
	NextCursor string
	HasMore    bool
}

// ChangeSource fetches incremental changes (IMAP/Gmail). nil disables sync.
type ChangeSource interface {
	FetchChanges(account ExternalAccount, cursor string, limit int) (ChangeBatch, error)
}

// Credential is an OAuth credential pair held by the SecretStore.
type Credential struct {
	AccessToken  string
	RefreshToken string
	Expiry       time.Time
}

// OAuthExchanger exchanges an auth code / refresh token with the provider.
type OAuthExchanger interface {
	Exchange(provider, authCode string) (email string, cred Credential, err error)
	Refresh(provider, refreshToken string) (Credential, error)
}

// OAuthAuthorizer builds the provider consent (authorization) URL for the front-channel
// half of the code grant (NR0003 gap A). It is an OPTIONAL capability: the handler
// type-asserts the configured OAuthExchanger to it, so back-channel-only fakes stay valid.
// The concrete oauthx.Exchanger implements it.
type OAuthAuthorizer interface {
	AuthCodeURL(provider, state string) (string, error)
}

// SecretStore holds external credentials out of SQL (DB0008 §2.3). Implementations
// must encrypt at rest in production; the in-memory/dev impl does not.
type SecretStore interface {
	Get(ref string) (Credential, bool)
	Put(ref string, cred Credential)
	Delete(ref string)
}

// Deps bundles the external-service ports + injectable clock for the handlers.
// Any port may be nil; the handlers degrade gracefully (e.g. nil Source -> sync
// returns UPSTREAM_UNAVAILABLE, nil Sender -> send returns SEND_FAILED).
type Deps struct {
	Sender  Sender
	Source  ChangeSource
	OAuth   OAuthExchanger
	Secrets SecretStore
	Blob    storage.Blob
	// States persists the authorize->callback state binding (server.0005 NR0009 gap A).
	// nil is auto-filled with an in-memory store by NewHandlers, so the front-channel
	// callback works out of the box (same default-on ethos as the dev SecretStore).
	States OAuthStateStore
	// OAuthReturnURL is the app URL the OAuth callback sends the browser back to after a
	// server-side code exchange (e.g. a Flutter deep link / custom-tab redirect target).
	// Empty -> the callback renders a self-contained "you may close this window" page the
	// in-app browser can detect instead of redirecting (server.0005 NR0009 §6-2).
	OAuthReturnURL string
	Now            func() time.Time
	// SendRetry overrides the L0010 §2.4 backoff policy for external send (zero
	// value -> retry.Default()). Tests set Base=0 to avoid real sleeps.
	SendRetry retry.Policy
}

func (d Deps) now() time.Time {
	if d.Now != nil {
		return d.Now()
	}
	return time.Now()
}

func (d Deps) sendRetry() retry.Policy {
	if d.SendRetry.MaxAttempts > 0 {
		return d.SendRetry
	}
	return retry.Default()
}
