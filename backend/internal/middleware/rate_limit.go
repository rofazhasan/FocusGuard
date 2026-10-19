package middleware

import (
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/focusguard/focusguard/backend/pkg/apierror"
)

const maxTrackedIPs = 20000

type rateLimiter struct {
	mu       sync.Mutex
	requests map[string][]time.Time
	limit    int
	window   time.Duration
}

func NewRateLimiter(limit int, window time.Duration) func(http.Handler) http.Handler {
	rl := &rateLimiter{
		requests: make(map[string][]time.Time),
		limit:    limit,
		window:   window,
	}

	// Periodic cleanup of stale entries
	go func() {
		ticker := time.NewTicker(rl.window * 2)
		for range ticker.C {
			rl.mu.Lock()
			cutoff := time.Now().Add(-rl.window)
			for ip, times := range rl.requests {
				var valid []time.Time
				for _, t := range times {
					if t.After(cutoff) {
						valid = append(valid, t)
					}
				}
				if len(valid) == 0 {
					delete(rl.requests, ip)
				} else {
					rl.requests[ip] = valid
				}
			}
			rl.mu.Unlock()
		}
	}()

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := getClientIP(r)
			reqID := GetRequestID(r.Context())

			rl.mu.Lock()
			now := time.Now()
			cutoff := now.Add(-rl.window)

			// Memory bound protection: if map grows excessively, evict stale keys immediately
			if len(rl.requests) >= maxTrackedIPs {
				for k, times := range rl.requests {
					if len(times) == 0 || !times[len(times)-1].After(cutoff) {
						delete(rl.requests, k)
					}
				}
			}

			var recent []time.Time
			for _, t := range rl.requests[ip] {
				if t.After(cutoff) {
					recent = append(recent, t)
				}
			}

			if len(recent) >= rl.limit {
				rl.mu.Unlock()
				apierror.Write(w, http.StatusTooManyRequests, apierror.CodeRateLimited, "Rate limit exceeded. Please try again shortly.", reqID)
				return
			}

			rl.requests[ip] = append(recent, now)
			rl.mu.Unlock()

			next.ServeHTTP(w, r)
		})
	}
}

func getClientIP(r *http.Request) string {
	forwarded := r.Header.Get("X-Forwarded-For")
	if forwarded != "" {
		parts := strings.Split(forwarded, ",")
		return strings.TrimSpace(parts[0])
	}
	realIP := r.Header.Get("X-Real-IP")
	if realIP != "" {
		return strings.TrimSpace(realIP)
	}
	parts := strings.Split(r.RemoteAddr, ":")
	if len(parts) > 0 {
		return parts[0]
	}
	return r.RemoteAddr
}
