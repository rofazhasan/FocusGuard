package auth

import (
	"strings"
	"testing"

	"github.com/google/uuid"
)

func TestArgon2idPasswordHashing(t *testing.T) {
	password := "FocusGuardSecure2026!"

	hash, err := HashPassword(password)
	if err != nil {
		t.Fatalf("Failed to hash password with Argon2id: %v", err)
	}

	if !strings.HasPrefix(hash, "$argon2id$") {
		t.Errorf("Expected Argon2id hash format, got: %s", hash)
	}

	if !CheckPasswordHash(password, hash) {
		t.Errorf("Password verification failed for correct password")
	}

	if CheckPasswordHash("wrongpassword", hash) {
		t.Errorf("Password verification unexpectedly succeeded for incorrect password")
	}
}

func TestDeviceTokenGeneration(t *testing.T) {
	tokenService := NewTokenService("test_secret_key_12345678901234567890")

	deviceID := uuid.New()
	userID := uuid.New()
	credVersion := 1

	token, err := tokenService.GenerateDeviceToken(deviceID, userID, credVersion)
	if err != nil {
		t.Fatalf("GenerateDeviceToken failed: %v", err)
	}

	claims, err := tokenService.ValidateToken(token)
	if err != nil {
		t.Fatalf("ValidateToken failed: %v", err)
	}

	if claims.Role != "DEVICE" {
		t.Errorf("Expected role DEVICE, got %s", claims.Role)
	}

	if claims.DeviceID != deviceID {
		t.Errorf("Expected DeviceID %s, got %s", deviceID, claims.DeviceID)
	}

	if claims.UserID != userID {
		t.Errorf("Expected UserID %s, got %s", userID, claims.UserID)
	}

	if claims.CredentialVersion != credVersion {
		t.Errorf("Expected CredentialVersion %d, got %d", credVersion, claims.CredentialVersion)
	}
}
