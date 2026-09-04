package requestid

import (
	"context"
	"net/http"

	"github.com/google/uuid"
)

const Header = "X-Request-ID"

type contextKey string

const ContextKey contextKey = "request_id"

func FromContext(ctx context.Context) string {
	if val, ok := ctx.Value(ContextKey).(string); ok && val != "" {
		return val
	}
	return ""
}

func Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reqID := r.Header.Get(Header)
		if reqID == "" {
			reqID = uuid.New().String()
		}

		w.Header().Set(Header, reqID)
		ctx := context.WithValue(r.Context(), ContextKey, reqID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
