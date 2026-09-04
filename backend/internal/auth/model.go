package auth

import (
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

type User struct {
	ID           uuid.UUID `json:"id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	CreatedAt    time.Time `json:"createdAt"`
	UpdatedAt    time.Time `json:"updatedAt"`
}

type RegisterRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type RefreshRequest struct {
	RefreshToken string `json:"refreshToken"`
}

type LogoutRequest struct {
	RefreshToken string `json:"refreshToken"`
}

type AuthResponse struct {
	AccessToken  string  `json:"accessToken"`
	RefreshToken string  `json:"refreshToken"`
	User         UserDto `json:"user"`
}

type RefreshResponse struct {
	AccessToken  string `json:"accessToken"`
	RefreshToken string `json:"refreshToken"`
}

type UserDto struct {
	ID    uuid.UUID `json:"id"`
	Email string    `json:"email"`
}

type MeResponse struct {
	User                UserDto `json:"user"`
	ActiveDevicesCount  int     `json:"activeDevicesCount"`
	ActivePoliciesCount int     `json:"activePoliciesCount"`
}

type Claims struct {
	UserID            uuid.UUID `json:"sub"`
	Email             string    `json:"email,omitempty"`
	Role              string    `json:"role,omitempty"` // "OWNER" | "DEVICE"
	DeviceID          uuid.UUID `json:"deviceId,omitempty"`
	CredentialVersion int       `json:"credentialVersion,omitempty"`
	jwt.RegisteredClaims
}
