package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidCredentials = errors.New("invalid email or password")
	ErrUserAlreadyExists  = errors.New("user with this email already exists")
	ErrSessionRevoked     = errors.New("session has been revoked or expired")
)

type TokenService struct {
	secretKey []byte
}

func NewTokenService(secretKey string) *TokenService {
	return &TokenService{
		secretKey: []byte(secretKey),
	}
}

// Argon2id Parameters
const (
	argonMemory      = 64 * 1024 // 64 MB
	argonIterations  = 1
	argonParallelism = 4
	argonSaltLength  = 16
	argonKeyLength   = 32
)

// HashPassword generates an Argon2id hash for new credentials
func HashPassword(password string) (string, error) {
	salt := make([]byte, argonSaltLength)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("failed to generate random salt: %w", err)
	}

	hash := argon2.IDKey([]byte(password), salt, argonIterations, argonMemory, argonParallelism, argonKeyLength)

	b64Salt := base64.RawStdEncoding.EncodeToString(salt)
	b64Hash := base64.RawStdEncoding.EncodeToString(hash)

	encoded := fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, argonMemory, argonIterations, argonParallelism, b64Salt, b64Hash)

	return encoded, nil
}

// CheckPasswordHash verifies a password against Argon2id or legacy bcrypt hashes
func CheckPasswordHash(password, storedHash string) bool {
	if strings.HasPrefix(storedHash, "$argon2id$") {
		parts := strings.Split(storedHash, "$")
		if len(parts) != 6 {
			return false
		}

		var version int
		var memory uint32
		var iterations uint32
		var parallelism uint8

		_, err := fmt.Sscanf(parts[2], "v=%d", &version)
		if err != nil {
			return false
		}
		_, err = fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &iterations, &parallelism)
		if err != nil {
			return false
		}

		salt, err := base64.RawStdEncoding.DecodeString(parts[4])
		if err != nil {
			return false
		}

		expectedHash, err := base64.RawStdEncoding.DecodeString(parts[5])
		if err != nil {
			return false
		}

		calculatedHash := argon2.IDKey([]byte(password), salt, iterations, memory, parallelism, uint32(len(expectedHash)))

		return subtle.ConstantTimeCompare(expectedHash, calculatedHash) == 1
	}

	// Legacy bcrypt fallback for seamless Phase 1 migration
	if strings.HasPrefix(storedHash, "$2a$") || strings.HasPrefix(storedHash, "$2b$") || strings.HasPrefix(storedHash, "$2y$") {
		err := bcrypt.CompareHashAndPassword([]byte(storedHash), []byte(password))
		return err == nil
	}

	return false
}

// GenerateTokens creates user tokens with Role: "OWNER"
func (s *TokenService) GenerateTokens(userID uuid.UUID, email string) (string, string, error) {
	now := time.Now().UTC()

	// Access Token (15-min expiry)
	accessClaims := Claims{
		UserID: userID,
		Email:  email,
		Role:   "OWNER",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(15 * time.Minute)),
			IssuedAt:  jwt.NewNumericDate(now),
			Subject:   userID.String(),
		},
	}
	accessToken := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims)
	accessSigned, err := accessToken.SignedString(s.secretKey)
	if err != nil {
		return "", "", fmt.Errorf("failed to sign access token: %w", err)
	}

	// Refresh Token (30-day expiry)
	refreshClaims := Claims{
		UserID: userID,
		Email:  email,
		Role:   "OWNER",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(30 * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(now),
			Subject:   userID.String(),
			ID:        uuid.New().String(), // Unique JTI for session tracking
		},
	}
	refreshToken := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims)
	refreshSigned, err := refreshToken.SignedString(s.secretKey)
	if err != nil {
		return "", "", fmt.Errorf("failed to sign refresh token: %w", err)
	}

	return accessSigned, refreshSigned, nil
}

// GenerateDeviceToken generates a dedicated token for enrolled devices
func (s *TokenService) GenerateDeviceToken(deviceID uuid.UUID, userID uuid.UUID, credentialVersion int) (string, error) {
	now := time.Now().UTC()

	// Device tokens have 7-day or 30-day lifespans and are validated against database status
	deviceClaims := Claims{
		UserID:            userID,
		DeviceID:          deviceID,
		CredentialVersion: credentialVersion,
		Role:              "DEVICE",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(30 * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(now),
			Subject:   deviceID.String(),
			ID:        uuid.New().String(),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, deviceClaims)
	return token.SignedString(s.secretKey)
}

func (s *TokenService) ValidateToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return s.secretKey, nil
	})

	if err != nil {
		return nil, fmt.Errorf("invalid token: %w", err)
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token claims")
	}

	return claims, nil
}
