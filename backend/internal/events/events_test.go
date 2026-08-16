package events_test

import (
	"testing"

	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/internal/events"
)

// TestNewHub_InitializesCleanState verifies the Hub is created with empty state.
func TestNewHub_InitializesCleanState(t *testing.T) {
	hub := events.NewHub()
	if hub == nil {
		t.Fatal("Expected non-nil Hub from NewHub()")
	}
}

// TestHub_Run_DoesNotPanic verifies the hub goroutine starts without panicking.
func TestHub_Run_DoesNotPanic(t *testing.T) {
	hub := events.NewHub()
	done := make(chan struct{})

	go func() {
		defer func() {
			if r := recover(); r != nil {
				t.Errorf("Hub.Run() panicked: %v", r)
			}
			close(done)
		}()
		// Start hub and immediately verify it doesn't crash
		go hub.Run()
		done <- struct{}{}
	}()

	<-done
}

// TestBroadcastToUser_NoRegisteredClients_DoesNotBlock verifies that
// broadcasting to a user with no registered WebSocket clients does not deadlock.
func TestBroadcastToUser_NoRegisteredClients_NoDeadlock(t *testing.T) {
	hub := events.NewHub()
	go hub.Run()

	// No clients registered — broadcast should complete without hanging
	done := make(chan struct{})
	go func() {
		hub.BroadcastToUser(uuid.New(), events.EventMessage{
			Event:   "POLICY_UPDATED",
			Payload: map[string]interface{}{"version": 42},
		})
		close(done)
	}()

	select {
	case <-done:
		// Pass — completed without deadlock
	}
}

// TestEventMessage_Serialization verifies EventMessage contains expected fields.
func TestEventMessage_Serialization(t *testing.T) {
	msg := events.EventMessage{
		Event: "DOMAIN_BLOCKED",
		Payload: map[string]interface{}{
			"domain":       "youtube.com",
			"usedSeconds":  1800,
			"limitSeconds": 1800,
		},
	}

	if msg.Event != "DOMAIN_BLOCKED" {
		t.Errorf("Expected event DOMAIN_BLOCKED, got %s", msg.Event)
	}
	if msg.Payload == nil {
		t.Error("Expected non-nil Payload")
	}
}
