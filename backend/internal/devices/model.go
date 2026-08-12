package devices

import (
	"time"

	"github.com/google/uuid"
)

type PlatformType string

const (
	PlatformMacOS   PlatformType = "MACOS"
	PlatformAndroid PlatformType = "ANDROID"
)

type DeviceStatus string

const (
	StatusOnline       DeviceStatus = "ONLINE"
	StatusOffline      DeviceStatus = "OFFLINE"
	StatusUnregistered DeviceStatus = "UNREGISTERED"
)

type Device struct {
	ID         uuid.UUID    `json:"id"`
	UserID     uuid.UUID    `json:"userId"`
	DeviceName string       `json:"deviceName"`
	Platform   PlatformType `json:"platform"`
	OSVersion  string       `json:"osVersion"`
	Status     DeviceStatus `json:"status"`
	LastSeenAt time.Time    `json:"lastSeenAt"`
	CreatedAt  time.Time    `json:"createdAt"`
}

type RegisterDeviceRequest struct {
	DeviceName string       `json:"deviceName"`
	Platform   PlatformType `json:"platform"`
	OSVersion  string       `json:"osVersion"`
}
