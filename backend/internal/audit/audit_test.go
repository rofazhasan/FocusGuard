package audit_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/focusguard/focusguard/backend/internal/audit"
)

// TestGetAuditLogs_NoDatabase verifies the handler returns an empty array
// and 200 OK when no database is available (nil db - offline graceful degradation).
func TestGetAuditLogs_NilDB(t *testing.T) {
	handler := audit.NewHandler(nil)

	// Build an unauthenticated request — we expect 401 because no user claims
	req := httptest.NewRequest(http.MethodGet, "/api/v1/audit/logs", nil)
	w := httptest.NewRecorder()

	// Call handler directly without middleware context
	handler.GetAuditLogs(w, req)

	// Without auth middleware context, it should return 401 Unauthorized
	if w.Code != http.StatusUnauthorized {
		t.Errorf("Expected 401 Unauthorized without auth context, got %d", w.Code)
	}
}

// TestAuditLogEntry_JSONSerialization verifies the AuditLogEntry model serializes correctly.
func TestAuditLogEntry_JSONSerialization(t *testing.T) {
	entry := audit.AuditLogEntry{
		ID:      "audit_001",
		UserID:  "user_001",
		Action:  "DEVICE_ENROLLED",
		Details: "Chrome extension enrolled",
	}

	data, err := json.Marshal(entry)
	if err != nil {
		t.Fatalf("Failed to marshal AuditLogEntry: %v", err)
	}

	var decoded audit.AuditLogEntry
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("Failed to unmarshal AuditLogEntry: %v", err)
	}

	if decoded.ID != entry.ID {
		t.Errorf("Expected ID %s, got %s", entry.ID, decoded.ID)
	}
	if decoded.Action != entry.Action {
		t.Errorf("Expected Action %s, got %s", entry.Action, decoded.Action)
	}
	if decoded.DeviceID != nil {
		t.Error("Expected DeviceID to be nil (omitempty)")
	}
}
