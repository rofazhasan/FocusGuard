package focus

import (
	"testing"
	"time"
)

func TestFocusSessionCountdown(t *testing.T) {
	durationMins := 45
	now := time.Now().UTC()
	endsAt := now.Add(time.Duration(durationMins) * time.Minute)

	diff := endsAt.Sub(now)
	if diff.Minutes() != float64(durationMins) {
		t.Errorf("Expected 45 minute duration, got %v", diff.Minutes())
	}
}
