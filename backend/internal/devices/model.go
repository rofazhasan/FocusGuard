package devices

import (
	"time"

	"github.com/google/uuid"
)

type PlatformType string

const (
	PlatformMacOS     PlatformType = "MACOS"
	PlatformAndroid   PlatformType = "ANDROID"
	PlatformWindows   PlatformType = "WINDOWS"
	PlatformLinux     PlatformType = "LINUX"
	PlatformExtension PlatformType = "EXTENSION"
	PlatformBrowser   PlatformType = "BROWSER"
)

type DeviceStatus string

const (
	StatusPending      DeviceStatus = "PENDING"
	StatusActive       DeviceStatus = "ACTIVE"
	StatusOnline       DeviceStatus = "ACTIVE" // Backward compatibility alias
	StatusOffline      DeviceStatus = "OFFLINE"
	StatusRevoked      DeviceStatus = "REVOKED"
	StatusSuspended    DeviceStatus = "SUSPENDED"
	StatusError        DeviceStatus = "ERROR"
	StatusUnregistered DeviceStatus = "UNREGISTERED"
)

type ClientType string

const (
	ClientExtension    ClientType = "EXTENSION"
	ClientMacOSAgent   ClientType = "MACOS_AGENT"
	ClientWindowsAgent ClientType = "WINDOWS_AGENT"
	ClientAndroidApp   ClientType = "ANDROID_APP"
	ClientTestClient   ClientType = "TEST_CLIENT"
)

type Device struct {
	ID              uuid.UUID    `json:"id"`
	UserID          uuid.UUID    `json:"userId"`
	PublicKey       string       `json:"publicKey,omitempty"`
	DeviceName      string       `json:"deviceName"`
	Platform        PlatformType `json:"platform"`
	ClientType      ClientType   `json:"clientType"`
	OSVersion       string       `json:"osVersion"`
	AppVersion      string       `json:"appVersion"`
	Status          DeviceStatus `json:"status"`
	ProtectionState string       `json:"protectionState"`
	PolicyVersion   int          `json:"policyVersion"`
	LastSeenAt      time.Time    `json:"lastSeenAt"`
	CreatedAt       time.Time    `json:"createdAt"`
	RevokedAt       *time.Time   `json:"revokedAt,omitempty"`
}

type RegisterDeviceRequest struct {
	DeviceName      string       `json:"deviceName"`
	Platform        PlatformType `json:"platform"`
	ClientType      ClientType   `json:"clientType"`
	OSVersion       string       `json:"osVersion"`
	AppVersion      string       `json:"appVersion"`
	PublicKey       string       `json:"publicKey,omitempty"`
	KeyAlgorithm    string       `json:"keyAlgorithm,omitempty"`
}

type HeartbeatRequest struct {
	AppVersion      string                 `json:"appVersion"`
	PolicyVersion   int                    `json:"policyVersion"`
	ProtectionState string                 `json:"protectionState"`
	HealthMetadata  map[string]interface{} `json:"healthMetadata,omitempty"`
	Timestamp       string                 `json:"timestamp"`
}

type HeartbeatResponse struct {
	Acknowledged        bool         `json:"acknowledged"`
	DeviceStatus        DeviceStatus `json:"deviceStatus"`
	LatestPolicyVersion int          `json:"latestPolicyVersion"`
	ServerTime          time.Time    `json:"serverTime"`
}

type RevokeDeviceResponse struct {
	Success   bool      `json:"success"`
	DeviceID  string    `json:"deviceId"`
	Status    string    `json:"status"`
	RevokedAt time.Time `json:"revokedAt"`
}
