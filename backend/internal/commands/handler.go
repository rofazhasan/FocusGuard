package commands

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/internal/events"
	"github.com/focusguard/focusguard/backend/internal/middleware"
	"github.com/focusguard/focusguard/backend/pkg/logger"
)

type DispatchCommandRequest struct {
	DeviceID    string                 `json:"deviceId"`
	CommandType string                 `json:"commandType"` // "REMOTE_FOCUS_START", "POLICY_UPDATE", "SYNC_REQUEST"
	DurationSec int                    `json:"durationSec"`
	Payload     map[string]interface{} `json:"payload"`
}

type RemoteCommandResponse struct {
	CommandID   string                 `json:"commandId"`
	DeviceID    string                 `json:"deviceId"`
	CommandType string                 `json:"commandType"`
	IssuedAt    time.Time              `json:"issuedAt"`
	ExpiresAt   time.Time              `json:"expiresAt"`
	Status      string                 `json:"status"`
	Payload     map[string]interface{} `json:"payload"`
}

type Handler struct {
	db    *sql.DB
	wsHub *events.Hub
}

func NewHandler(db *sql.DB, wsHub *events.Hub) *Handler {
	return &Handler{
		db:    db,
		wsHub: wsHub,
	}
}

func (h *Handler) DispatchCommand(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var req DispatchCommandRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Invalid request payload"}`, http.StatusBadRequest)
		return
	}

	if req.DeviceID == "" || req.CommandType == "" {
		http.Error(w, `{"error":"DeviceID and CommandType required"}`, http.StatusBadRequest)
		return
	}

	commandID := uuid.New().String()
	now := time.Now().UTC()
	ttl := 15 * time.Minute
	if req.DurationSec > 0 {
		ttl = time.Duration(req.DurationSec) * time.Second
	}
	expiresAt := now.Add(ttl)

	payloadBytes, _ := json.Marshal(req.Payload)
	payloadStr := string(payloadBytes)

	if h.db != nil {
		q := `INSERT INTO remote_commands (id, device_id, issued_by, command_type, payload, issued_at, expires_at, status)
		      VALUES ($1, $2, $3, $4, $5, $6, $7, 'DISPATCHED')`
		_, err := h.db.ExecContext(r.Context(), q, commandID, req.DeviceID, claims.UserID.String(), req.CommandType, payloadStr, now, expiresAt)
		if err != nil {
			logger.Error("Failed to persist remote command", "error", err)
			http.Error(w, `{"error":"Database error dispatching command"}`, http.StatusInternalServerError)
			return
		}

		// Record in audit log
		auditQ := `INSERT INTO audit_logs (id, user_id, device_id, action, details, timestamp)
		          VALUES ($1, $2, $3, 'REMOTE_COMMAND_DISPATCHED', $4, CURRENT_TIMESTAMP)`
		_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), claims.UserID.String(), req.DeviceID, req.CommandType)
	}

	// Broadcast command over WebSocket to target device
	if h.wsHub != nil {
		h.wsHub.BroadcastToUser(claims.UserID, events.EventMessage{
			Event: "REMOTE_COMMAND",
			Payload: map[string]interface{}{
				"commandId":   commandID,
				"deviceId":    req.DeviceID,
				"commandType": req.CommandType,
				"issuedAt":    now.Unix(),
				"expiresAt":   expiresAt.Unix(),
				"payload":     req.Payload,
			},
		})
	}

	resp := RemoteCommandResponse{
		CommandID:   commandID,
		DeviceID:    req.DeviceID,
		CommandType: req.CommandType,
		IssuedAt:    now,
		ExpiresAt:   expiresAt,
		Status:      "DISPATCHED",
		Payload:     req.Payload,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(resp)
}
