package commands

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
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
		targetDevices := []string{req.DeviceID}
		if req.DeviceID == "ALL" {
			targetDevices = []string{}
			rows, err := h.db.QueryContext(r.Context(), `SELECT id FROM devices WHERE user_id = $1 AND status != 'REVOKED'`, claims.UserID.String())
			if err == nil {
				defer rows.Close()
				for rows.Next() {
					var devID string
					if err := rows.Scan(&devID); err == nil {
						targetDevices = append(targetDevices, devID)
					}
				}
			}
		}

		for _, dID := range targetDevices {
			q := `INSERT INTO remote_commands (id, device_id, issued_by, command_type, payload, issued_at, expires_at, status)
			      VALUES ($1, $2, $3, $4, $5, $6, $7, 'DISPATCHED')`
			_, _ = h.db.ExecContext(r.Context(), q, uuid.New().String(), dID, claims.UserID.String(), req.CommandType, payloadStr, now, expiresAt)
		}

		// Update device protection state according to command
		if req.CommandType == "STOP_APP" || req.CommandType == "LOCKDOWN_DEVICE" {
			if req.DeviceID == "ALL" {
				_, _ = h.db.ExecContext(r.Context(), `UPDATE devices SET protection_state = 'LOCKED' WHERE user_id = $1`, claims.UserID.String())
			} else {
				_, _ = h.db.ExecContext(r.Context(), `UPDATE devices SET protection_state = 'LOCKED' WHERE id = $1 AND user_id = $2`, req.DeviceID, claims.UserID.String())
			}
		} else if req.CommandType == "RESUME_APP" || req.CommandType == "UNLOCK_DEVICE" {
			if req.DeviceID == "ALL" {
				_, _ = h.db.ExecContext(r.Context(), `UPDATE devices SET protection_state = 'PROTECTED' WHERE user_id = $1`, claims.UserID.String())
			} else {
				_, _ = h.db.ExecContext(r.Context(), `UPDATE devices SET protection_state = 'PROTECTED' WHERE id = $1 AND user_id = $2`, req.DeviceID, claims.UserID.String())
			}
		}

		// Record in audit log
		auditQ := `INSERT INTO audit_logs (id, user_id, device_id, action, details, timestamp)
		          VALUES ($1, $2, $3, 'REMOTE_COMMAND_DISPATCHED', $4, CURRENT_TIMESTAMP)`
		_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), claims.UserID.String(), req.DeviceID, req.CommandType)
	}

	// Broadcast command over WebSocket to target devices in real-time
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

type AcknowledgeCommandRequest struct {
	Status  string                 `json:"status"` // "ACKNOWLEDGED", "EXECUTING", "SUCCEEDED", "FAILED"
	Details string                 `json:"details,omitempty"`
	Payload map[string]interface{} `json:"payload,omitempty"`
}

func (h *Handler) AcknowledgeCommand(w http.ResponseWriter, r *http.Request) {
	cmdID := chi.URLParam(r, "id")
	if cmdID == "" {
		http.Error(w, `{"error":"Command ID is required"}`, http.StatusBadRequest)
		return
	}

	var req AcknowledgeCommandRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		req.Status = "SUCCEEDED"
	}
	if req.Status == "" {
		req.Status = "SUCCEEDED"
	}

	if h.db != nil {
		q := `UPDATE remote_commands SET status = $1 WHERE id = $2`
		_, err := h.db.ExecContext(r.Context(), q, req.Status, cmdID)
		if err != nil {
			logger.Error("Failed to update command acknowledgement status", "error", err, "commandId", cmdID)
			http.Error(w, `{"error":"Database error updating command status"}`, http.StatusInternalServerError)
			return
		}

		auditQ := `INSERT INTO audit_logs (id, user_id, action, details, timestamp)
		          VALUES ($1, 'system', 'REMOTE_COMMAND_ACK', $2, CURRENT_TIMESTAMP)`
		_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), "Command "+cmdID+" status: "+req.Status)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"commandId": cmdID,
		"status":    req.Status,
		"updatedAt": time.Now().UTC().Format(time.RFC3339),
	})
}

func (h *Handler) GetPendingCommands(w http.ResponseWriter, r *http.Request) {
	deviceID := r.URL.Query().Get("deviceId")
	if devCtx, ok := middleware.GetDeviceClaims(r.Context()); ok {
		deviceID = devCtx.DeviceID.String()
	}

	if deviceID == "" {
		http.Error(w, `{"error":"deviceId parameter required"}`, http.StatusBadRequest)
		return
	}

	commands := []RemoteCommandResponse{}
	if h.db != nil {
		q := `SELECT id, device_id, command_type, issued_at, expires_at, status, payload
		      FROM remote_commands
		      WHERE device_id = $1 AND status IN ('PENDING', 'DISPATCHED') AND expires_at > CURRENT_TIMESTAMP
		      ORDER BY issued_at ASC`
		rows, err := h.db.QueryContext(r.Context(), q, deviceID)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var cmd RemoteCommandResponse
				var pStr string
				if err := rows.Scan(&cmd.CommandID, &cmd.DeviceID, &cmd.CommandType, &cmd.IssuedAt, &cmd.ExpiresAt, &cmd.Status, &pStr); err == nil {
					var pMap map[string]interface{}
					if err := json.Unmarshal([]byte(pStr), &pMap); err == nil {
						cmd.Payload = pMap
					}
					commands = append(commands, cmd)
				}
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"commands": commands,
		"count":    len(commands),
	})
}

