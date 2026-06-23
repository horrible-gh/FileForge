// Package httpx implements the P0007 §1 common response envelope and JSON helpers.
package httpx

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"

	"mailanchor/serverd/internal/apperr"
)

// success envelope: { ok:true, data, meta? }
type successEnvelope struct {
	OK   bool `json:"ok"`
	Data any  `json:"data"`
	Meta any  `json:"meta,omitempty"`
}

// error envelope: { ok:false, error:{ code, message, details?, request_id } }
type errorEnvelope struct {
	OK    bool         `json:"ok"`
	Error errorPayload `json:"error"`
}

type errorPayload struct {
	Code      string         `json:"code"`
	Message   string         `json:"message"`
	Details   map[string]any `json:"details,omitempty"`
	RequestID string         `json:"request_id"`
}

// OK writes a 200/201 success envelope.
func OK(w http.ResponseWriter, status int, data any) {
	writeJSON(w, status, successEnvelope{OK: true, Data: data})
}

// OKMeta writes a success envelope carrying pagination/extra meta.
func OKMeta(w http.ResponseWriter, status int, data, meta any) {
	writeJSON(w, status, successEnvelope{OK: true, Data: data, Meta: meta})
}

// NoContent writes a 204 with no body (P0007 §1.3).
func NoContent(w http.ResponseWriter) { w.WriteHeader(http.StatusNoContent) }

// Error maps any error to the P0007 error envelope. Non-AppErrors collapse to INTERNAL.
func Error(w http.ResponseWriter, err error) {
	var ae *apperr.AppError
	if !errors.As(err, &ae) {
		ae = apperr.Internal
	}
	writeJSON(w, ae.Status, errorEnvelope{
		OK: false,
		Error: errorPayload{
			Code:      ae.Code,
			Message:   ae.Message,
			Details:   ae.Details,
			RequestID: newRequestID(),
		},
	})
}

// DecodeJSON strictly decodes a JSON request body, returning VALIDATION_FAILED on failure.
func DecodeJSON(r *http.Request, dst any) error {
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return apperr.ValidationFailed.WithDetails(map[string]any{"reason": err.Error()})
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func newRequestID() string {
	var b [12]byte
	_, _ = rand.Read(b[:])
	return "req_" + hex.EncodeToString(b[:])
}
