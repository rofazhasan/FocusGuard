package pairing

import (
	"time"

	"github.com/google/uuid"
)

type SessionStatus string

const (
	StatusCreated         SessionStatus = "CREATED"
	StatusScanned         SessionStatus = "SCANNED"
	StatusPendingApproval SessionStatus = "PENDING_APPROVAL"
	StatusApproved        SessionStatus = "APPROVED"
	StatusConsumed        SessionStatus = "CONSUMED"
	StatusExpired         SessionStatus = "EXPIRED"
	StatusCancelled       SessionStatus = "CANCELLED"
	StatusRejected        SessionStatus = "REJECTED"
	StatusRevoked         SessionStatus = "REVOKED"
)

type CreateSessionRequest struct {
	DeviceName string `json:"deviceName,omitempty"`
	TargetRole string `json:"targetRole,omitempty"`
}

type CreateSessionResponse struct {
	SessionID    uuid.UUID     `json:"sessionId"`
	PairingCode  string        `json:"pairingCode"`
	QRPayload    string        `json:"qrPayload"`
	Status       SessionStatus `json:"status"`
	ExpiresAt    time.Time     `json:"expiresAt"`
	ExpiresInSec int           `json:"expiresInSec"`
}

type EnrollmentRequest struct {
	PairingCode  string `json:"pairingCode,omitempty"`
	DeviceName   string `json:"deviceName"`
	Platform     string `json:"platform"`
	ClientType   string `json:"clientType"`
	AppVersion   string `json:"appVersion"`
	PublicKey    string `json:"publicKey"`
	KeyAlgorithm string `json:"keyAlgorithm,omitempty"`
}

type PairingSessionDetail struct {
	SessionID              uuid.UUID              `json:"sessionId"`
	OwnerUserID            uuid.UUID              `json:"ownerUserId"`
	Status                 SessionStatus          `json:"status"`
	RequestedDeviceMetadata map[string]interface{} `json:"requestedDeviceMetadata,omitempty"`
	EnrolledDeviceID       *uuid.UUID             `json:"enrolledDeviceId,omitempty"`
	ExpiresAt              time.Time              `json:"expiresAt"`
	ExpiresInSec           int                    `json:"expiresInSec"`
	CreatedAt              time.Time              `json:"createdAt"`
}

type DeviceStatusPollResponse struct {
	Status      SessionStatus `json:"status"`
	DeviceID    string        `json:"deviceId,omitempty"`
	DeviceToken string        `json:"deviceToken,omitempty"`
	ServerTime  time.Time     `json:"serverTime"`
}
