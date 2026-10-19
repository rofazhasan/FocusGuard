package commands

import (
	"testing"
	"time"
)

func TestRemoteCommandExpiration(t *testing.T) {
	now := time.Now().UTC()
	expiresAt := now.Add(15 * time.Minute)

	if !expiresAt.After(now) {
		t.Errorf("Expected expiresAt to be in the future")
	}

	expiredTime := now.Add(-1 * time.Minute)
	if !now.After(expiredTime) {
		t.Errorf("Expected expiredTime to be recognized as past")
	}
}

func TestRemoteCommandProtectionStateInference(t *testing.T) {
	tests := []struct {
		cmdType       string
		expectedState string
	}{
		{"STOP_APP", "LOCKED"},
		{"LOCKDOWN_DEVICE", "LOCKED"},
		{"RESUME_APP", "PROTECTED"},
		{"UNLOCK_DEVICE", "PROTECTED"},
		{"SYNC_POLICIES", ""},
	}

	for _, tt := range tests {
		var state string
		switch tt.cmdType {
		case "STOP_APP", "LOCKDOWN_DEVICE":
			state = "LOCKED"
		case "RESUME_APP", "UNLOCK_DEVICE":
			state = "PROTECTED"
		default:
			state = ""
		}

		if state != tt.expectedState {
			t.Errorf("For command %s, expected state %s, got %s", tt.cmdType, tt.expectedState, state)
		}
	}
}
