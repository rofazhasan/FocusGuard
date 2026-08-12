package auth

import (
	"testing"

	"github.com/google/uuid"
)

func TestPasswordHashing(t *testing.T) {
	password := "SecureP@ssw0rd2026!"

	hash, err := HashPassword(password)
	if err != nil {
		t.Fatalf("unexpected error hashing password: %v", err)
	}

	if !CheckPasswordHash(password, hash) {
		t.Errorf("expected password verification to succeed for valid password")
	}

	if CheckPasswordHash("WrongPassword", hash) {
		t.Errorf("expected password verification to fail for invalid password")
	}
}

func TestJWTTokenGenerationAndValidation(t *testing.T) {
	secret := "test_secret_key_12345"
	svc := NewTokenService(secret)

	userID := uuid.New()
	email := "testuser@focusguard.com"

	access, refresh, err := svc.GenerateTokens(userID, email)
	if err != nil {
		t.Fatalf("unexpected error generating tokens: %v", err)
	}

	if access == "" || refresh == "" {
		t.Fatalf("expected non-empty tokens")
	}

	claims, err := svc.ValidateToken(access)
	if err != nil {
		t.Fatalf("unexpected error validating access token: %v", err)
	}

	if claims.UserID != userID {
		t.Errorf("expected userID %s, got %s", userID, claims.UserID)
	}

	if claims.Email != email {
		t.Errorf("expected email %s, got %s", email, claims.Email)
	}
}
