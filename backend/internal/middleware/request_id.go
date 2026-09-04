package middleware

import (
	"context"
	"net/http"

	"github.com/focusguard/focusguard/backend/pkg/requestid"
)

func RequestIDMiddleware(next http.Handler) http.Handler {
	return requestid.Middleware(next)
}

func GetRequestID(ctx context.Context) string {
	return requestid.FromContext(ctx)
}
