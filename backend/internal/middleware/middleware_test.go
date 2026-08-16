package middleware_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/internal/auth"
	"github.com/focusguard/focusguard/backend/internal/middleware"
)

func makeTokenService() *auth.TokenService {
	return auth.NewTokenService("test_jwt_secret_focusguard_2026")
}

// TestAuthMiddleware_MissingHeader_Returns401 verifies missing Authorization returns 401.
func TestAuthMiddleware_MissingHeader_Returns401(t *testing.T) {
	svc := makeTokenService()
	mw := middleware.AuthMiddleware(svc)

	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/api/v1/policies", nil)
	w := httptest.NewRecorder()

	mw(next).ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401, got %d", w.Code)
	}
}

// TestAuthMiddleware_InvalidToken_Returns401 verifies a tampered token returns 401.
func TestAuthMiddleware_InvalidToken_Returns401(t *testing.T) {
	svc := makeTokenService()
	mw := middleware.AuthMiddleware(svc)

	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/api/v1/policies", nil)
	req.Header.Set("Authorization", "Bearer totally.invalid.token")
	w := httptest.NewRecorder()

	mw(next).ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401, got %d", w.Code)
	}
}

// TestAuthMiddleware_ValidToken_PassesThrough verifies a valid JWT sets user context and allows the handler.
func TestAuthMiddleware_ValidToken_PassesThrough(t *testing.T) {
	svc := makeTokenService()
	mw := middleware.AuthMiddleware(svc)

	userID := uuid.New()
	accessToken, _, err := svc.GenerateTokens(userID, "test@focusguard.local")
	if err != nil {
		t.Fatalf("Failed to generate test token: %v", err)
	}

	var capturedUserID uuid.UUID
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims, ok := middleware.GetUserClaims(r.Context())
		if !ok {
			t.Error("Expected user claims in context")
			return
		}
		capturedUserID = claims.UserID
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/api/v1/policies", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	w := httptest.NewRecorder()

	mw(next).ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("Expected 200 with valid token, got %d", w.Code)
	}
	if capturedUserID != userID {
		t.Errorf("Expected userID %s, got %s", userID, capturedUserID)
	}
}

// TestAuthMiddleware_MalformedBearer_Returns401 verifies "Bearer " prefix without token returns 401.
func TestAuthMiddleware_MalformedBearer_Returns401(t *testing.T) {
	svc := makeTokenService()
	mw := middleware.AuthMiddleware(svc)

	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/api/v1/policies", nil)
	req.Header.Set("Authorization", "Token some_not_bearer")
	w := httptest.NewRecorder()

	mw(next).ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 for malformed bearer, got %d", w.Code)
	}
}

// TestGetUserClaims_EmptyContext_ReturnsFalse verifies empty context returns (nil, false).
func TestGetUserClaims_EmptyContext_ReturnsFalse(t *testing.T) {
	claims, ok := middleware.GetUserClaims(context.Background())
	if ok || claims != nil {
		t.Error("Expected (nil, false) from empty context")
	}
}
