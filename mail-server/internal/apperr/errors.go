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
	ValidationFailed = New("VALIDATION_FAILED", http.StatusBadRequest, "요청 형식 또는 필수값이 올바르지 않습니다.")
	AuthInvalidCreds = New("AUTH_INVALID_CREDENTIALS", http.StatusUnauthorized, "이메일 또는 비밀번호가 올바르지 않습니다.")
	// TwoFactorInvalid extends the P0007 §5 catalog for the R0001 stage-4 2FA flow: a wrong
	// or missing TOTP/recovery code on login, activate, disable, or recovery regeneration.
	TwoFactorInvalid   = New("TWO_FACTOR_INVALID", http.StatusUnauthorized, "2단계 인증 코드가 올바르지 않습니다.")
	TokenExpired       = New("TOKEN_EXPIRED", http.StatusUnauthorized, "세션이 만료되었습니다. 다시 시도해 주세요.")
	TokenInvalid       = New("TOKEN_INVALID", http.StatusUnauthorized, "인증 토큰이 유효하지 않습니다.")
	Forbidden          = New("FORBIDDEN", http.StatusForbidden, "접근 권한이 없습니다.")
	MailNotFound       = New("MAIL_NOT_FOUND", http.StatusNotFound, "요청한 메일을 찾을 수 없습니다.")
	AttachmentNotFound = New("ATTACHMENT_NOT_FOUND", http.StatusNotFound, "첨부를 찾을 수 없습니다.")
	LabelNotFound      = New("LABEL_NOT_FOUND", http.StatusNotFound, "라벨을 찾을 수 없습니다.")
	DraftConflict      = New("DRAFT_CONFLICT", http.StatusConflict, "다른 곳에서 초안이 수정되었습니다.")
	LabelDuplicate     = New("LABEL_DUPLICATE", http.StatusConflict, "같은 이름의 라벨이 이미 있습니다.")
	// AccountConflict extends the P0007 §5 catalog (UNIQUE(user_id,email) violation on
	// POST /accounts). Undefined codes are handled by clients as a general 409.
	AccountConflict  = New("ACCOUNT_DUPLICATE", http.StatusConflict, "이미 연결된 계정입니다.")
	RecipientInvalid = New("RECIPIENT_INVALID", http.StatusUnprocessableEntity, "받는이 주소 형식이 올바르지 않습니다.")
	// PayloadTooLarge extends the P0007 §5 catalog for over-limit uploads (NR0011 S4).
	PayloadTooLarge     = New("PAYLOAD_TOO_LARGE", http.StatusRequestEntityTooLarge, "첨부 용량이 허용 한도를 초과했습니다.")
	SendFailed          = New("SEND_FAILED", http.StatusBadGateway, "메일 발송에 실패했습니다. 잠시 후 다시 시도해 주세요.")
	UpstreamUnavailable = New("UPSTREAM_UNAVAILABLE", http.StatusServiceUnavailable, "외부 메일 서비스를 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.")
	Internal            = New("INTERNAL", http.StatusInternalServerError, "내부 오류가 발생했습니다.")
)
