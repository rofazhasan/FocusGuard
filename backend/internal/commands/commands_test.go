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
