package events

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/internal/middleware"
	"github.com/focusguard/focusguard/backend/pkg/apierror"
	"github.com/focusguard/focusguard/backend/pkg/requestid"
)

type BatchHandler struct {
	db    *sql.DB
	wsHub *Hub
}

func NewBatchHandler(db *sql.DB, wsHub *Hub) *BatchHandler {
	return &BatchHandler{
		db:    db,
		wsHub: wsHub,
	}
}

type EventDto struct {
	ID        string                 `json:"id"`
	DeviceID  string                 `json:"deviceId,omitempty"`
	EventType string                 `json:"eventType"`
	Domain    string                 `json:"domain,omitempty"`
	PolicyID  string                 `json:"policyId,omitempty"`
	Reason    string                 `json:"reason,omitempty"`
	Timestamp string                 `json:"timestamp"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
}

type BatchEventRequest struct {
	Events []EventDto `json:"events"`
}

type BatchEventResponse struct {
	Success    bool `json:"success"`
	Processed  int  `json:"processed"`
	Duplicates int  `json:"duplicates"`
}

const maxBatchSize = 100

func (h *BatchHandler) HandleBatchEvents(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())

	var userID uuid.UUID
	var authDeviceID string

	if devCtx, ok := middleware.GetDeviceClaims(r.Context()); ok {
		userID = devCtx.UserID
		authDeviceID = devCtx.DeviceID.String()
	} else if claims, ok := middleware.GetUserClaims(r.Context()); ok {
		userID = claims.UserID
		if claims.DeviceID != uuid.Nil {
			authDeviceID = claims.DeviceID.String()
		}
	} else {
		apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Unauthorized", reqID)
		return
	}

	var req BatchEventRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Invalid batch event payload", reqID)
		return
	}

	if len(req.Events) > maxBatchSize {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Batch size exceeds limit of 100 events", reqID)
		return
	}

	processed := 0
	duplicates := 0

	for _, evt := range req.Events {
		eventID := evt.ID
		if eventID == "" {
			eventID = uuid.New().String()
		}

		parsedEvtID, err := uuid.Parse(eventID)
		if err != nil {
			parsedEvtID = uuid.NewSHA1(uuid.NameSpaceOID, []byte(eventID))
		}

		targetVal := evt.Domain
		if targetVal == "" && evt.Metadata != nil {
			if t, ok := evt.Metadata["target"].(string); ok {
				targetVal = t
			}
		}

		reason := evt.Reason
		if reason == "" {
			reason = "FocusGuard event"
		}

		// Device ID scoping: use authenticated device ID if present, otherwise event device ID or fallback
		devID := authDeviceID
		if devID == "" {
			devID = evt.DeviceID
		}
		if devID == "" {
			devID = "00000000-0000-0000-0000-000000000002"
		}

		policyID := evt.PolicyID
		var policyIDVal interface{} = nil
		if policyID != "" {
			if pUUID, err := uuid.Parse(policyID); err == nil {
				policyIDVal = pUUID.String()
			}
		}

		eventType := evt.EventType
		if eventType == "" {
			eventType = "DOMAIN_BLOCKED"
		}

		if h.db != nil {
			// Idempotent insertion into blocked_events or audit logs
			q := `INSERT INTO blocked_events (id, user_id, device_id, policy_id, target_value, timestamp)
			      VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP)`
			_, err := h.db.ExecContext(r.Context(), q, parsedEvtID.String(), userID.String(), devID, policyIDVal, targetVal)
			if err != nil {
				// Duplicate event ID: safely ignore and count as duplicate
				duplicates++
				continue
			}
			processed++

			// Also log to audit logs
			auditQ := `INSERT INTO audit_logs (id, user_id, device_id, action, details, actor_type, actor_id, request_id, timestamp)
			          VALUES ($1, $2, $3, $4, $5, 'DEVICE', $6, $7, CURRENT_TIMESTAMP)`
			_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), userID.String(), devID,
				eventType, targetVal+" ("+reason+")", devID, reqID)
		} else {
			processed++
		}

		// Broadcast to Dashboard real-time feed
		if h.wsHub != nil {
			h.wsHub.BroadcastToUser(userID, EventMessage{
				Event: eventType,
				Payload: map[string]interface{}{
					"id":        parsedEvtID.String(),
					"deviceId":  devID,
					"domain":    targetVal,
					"reason":    reason,
					"timestamp": time.Now().UTC().Format(time.RFC3339),
				},
			})
		}
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(BatchEventResponse{
		Success:    true,
		Processed:  processed,
		Duplicates: duplicates,
	})
}
