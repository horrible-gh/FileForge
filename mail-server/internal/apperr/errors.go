// Package apperr defines the stable error catalog (P0007 §5) and the AppError type
// that carries an HTTP status + machine-stable code through the handler stack.
package apperr

import "net/http"

// AppError is a domain error mapped 1:1 to a P0007 error envelope.
type AppError struct {
	Code    string         // machine-stable code; clients branch on this only
	Status  int            // HTTP status (must match envelope ok=false)
	Message string         // human-readable; locale via Accept-Language (not for branching)
	Details map[string]any // optional diagnostics (violating field, conflict id...)
}

func (e *AppError) Error() string { return e.Code + ": " + e.Message }

// WithDetails returns a copy carrying diagnostic details.
func (e *AppError) WithDetails(d map[string]any) *AppError {
	cp := *e
	cp.Details = d
	return &cp
}

// New builds an ad-hoc AppError.
func New(code string, status int, msg string) *AppError {
	return &AppError{Code: code, Status: status, Message: msg}
}

// P0007 §5 error catalog. Messages default to ko (Accept-Language negotiation deferred).
var (
	ValidationFailed = New("VALIDATION_FAILED", http.StatusBadRequest, "The request format or required values are invalid.")
	AuthInvalidCreds = New("AUTH_INVALID_CREDENTIALS", http.StatusUnauthorized, "Email or password is incorrect.")
	// TwoFactorInvalid extends the P0007 §5 catalog for the R0001 stage-4 2FA flow: a wrong
	// or missing TOTP/recovery code on login, activate, disable, or recovery regeneration.
	TwoFactorInvalid   = New("TWO_FACTOR_INVALID", http.StatusUnauthorized, "The two-factor authentication code is invalid.")
	TokenExpired       = New("TOKEN_EXPIRED", http.StatusUnauthorized, "Your session has expired. Please try again.")
	TokenInvalid       = New("TOKEN_INVALID", http.StatusUnauthorized, "The authentication token is invalid.")
	Forbidden          = New("FORBIDDEN", http.StatusForbidden, "You do not have permission to access this resource.")
	MailNotFound       = New("MAIL_NOT_FOUND", http.StatusNotFound, "The requested email could not be found.")
	AttachmentNotFound = New("ATTACHMENT_NOT_FOUND", http.StatusNotFound, "The attachment could not be found.")
	LabelNotFound      = New("LABEL_NOT_FOUND", http.StatusNotFound, "The label could not be found.")
	DraftConflict      = New("DRAFT_CONFLICT", http.StatusConflict, "The draft was modified elsewhere.")
	LabelDuplicate     = New("LABEL_DUPLICATE", http.StatusConflict, "A label with the same name already exists.")
	// AccountConflict extends the P0007 §5 catalog (UNIQUE(user_id,email) violation on
	// POST /accounts). Undefined codes are handled by clients as a general 409.
	AccountConflict  = New("ACCOUNT_DUPLICATE", http.StatusConflict, "This account is already connected.")
	RecipientInvalid = New("RECIPIENT_INVALID", http.StatusUnprocessableEntity, "Recipient address format is invalid.")
	// PayloadTooLarge extends the P0007 §5 catalog for over-limit uploads (NR0011 S4).
	PayloadTooLarge     = New("PAYLOAD_TOO_LARGE", http.StatusRequestEntityTooLarge, "The attachment size exceeds the allowed limit.")
	SendFailed          = New("SEND_FAILED", http.StatusBadGateway, "Failed to send email. Please try again later.")
	UpstreamUnavailable = New("UPSTREAM_UNAVAILABLE", http.StatusServiceUnavailable, "The external mail service is unavailable. Please try again later.")
	Internal            = New("INTERNAL", http.StatusInternalServerError, "An internal error occurred.")
)
