package apierror

import (
	"encoding/json"
	"net/http"
)

type APIError struct {
	HTTPStatus int    `json:"-"`
	Code       string `json:"code"`
	Message    string `json:"message"`
	RequestID  string `json:"requestId,omitempty"`
}

type ErrorEnvelope struct {
	Error APIError `json:"error"`
}

// Canonical Error Codes
const (
	CodeAuthInvalid        = "AUTH_INVALID"
	CodeAuthExpired        = "AUTH_EXPIRED"
	CodeAuthRevoked        = "AUTH_REVOKED"
	CodeDeviceNotFound     = "DEVICE_NOT_FOUND"
	CodeDeviceRevoked      = "DEVICE_REVOKED"
	CodeDeviceSuspended    = "DEVICE_SUSPENDED"
	CodePairingNotFound    = "PAIRING_NOT_FOUND"
	CodePairingExpired     = "PAIRING_EXPIRED"
	CodePairingConsumed    = "PAIRING_CONSUMED"
	CodePairingInvalidState = "PAIRING_INVALID_STATE"
	CodePairingUnauthorized = "PAIRING_UNAUTHORIZED"
	CodeValidationError    = "VALIDATION_ERROR"
	CodeRateLimited        = "RATE_LIMITED"
	CodeInternalError      = "INTERNAL_ERROR"
)

func New(httpStatus int, code string, message string, requestID string) *APIError {
	return &APIError{
		HTTPStatus: httpStatus,
		Code:       code,
		Message:    message,
		RequestID:  requestID,
	}
}

func Write(w http.ResponseWriter, httpStatus int, code string, message string, requestID string) {
	w.Header().Set("Content-Type", "application/json")
	if requestID != "" {
		w.Header().Set("X-Request-ID", requestID)
	}
	w.WriteHeader(httpStatus)
	_ = json.NewEncoder(w).Encode(ErrorEnvelope{
		Error: APIError{
			Code:      code,
			Message:   message,
			RequestID: requestID,
		},
	})
}
