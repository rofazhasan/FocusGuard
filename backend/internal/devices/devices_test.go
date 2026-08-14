package devices

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestDeviceRegistrationPayload(t *testing.T) {
	req := RegisterDeviceRequest{
		DeviceName: "MacBook Pro 16\"",
		Platform:   PlatformMacOS,
		OSVersion:  "macOS 15.0",
	}

	if req.DeviceName == "" {
		t.Errorf("Device name should not be empty")
	}
	if req.Platform != PlatformMacOS {
		t.Errorf("Expected platform %s, got %s", PlatformMacOS, req.Platform)
	}

	dev := Device{
		ID:         uuid.New(),
		UserID:     uuid.New(),
		DeviceName: req.DeviceName,
		Platform:   req.Platform,
		OSVersion:  req.OSVersion,
		Status:     StatusOnline,
		LastSeenAt: time.Now().UTC(),
		CreatedAt:  time.Now().UTC(),
	}

	if dev.Status != StatusOnline {
		t.Errorf("Expected status %s, got %s", StatusOnline, dev.Status)
	}
}
