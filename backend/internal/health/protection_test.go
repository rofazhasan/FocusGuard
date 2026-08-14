package health

import (
	"testing"
)

func TestCalculateProtectionScore(t *testing.T) {
	// Full 100% protection
	score100, state100 := CalculateProtectionScore(true, true, true, true)
	if score100 != 100 || state100 != "ACTIVE" {
		t.Fatalf("Expected 100 / ACTIVE, got %d / %s", score100, state100)
	}

	// Degraded protection (VPN dropped)
	score75, state75 := CalculateProtectionScore(false, true, true, true)
	if score75 != 75 || state75 != "DEGRADED" {
		t.Fatalf("Expected 75 / DEGRADED, got %d / %s", score75, state75)
	}

	// Permission required (Usage access revoked)
	score50, state50 := CalculateProtectionScore(false, true, false, true)
	if score50 != 50 || state50 != "PERMISSION_REQUIRED" {
		t.Fatalf("Expected 50 / PERMISSION_REQUIRED, got %d / %s", score50, state50)
	}
}
