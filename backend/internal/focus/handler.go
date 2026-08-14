package focus

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

type StartFocusRequest struct {
	DurationMinutes int      `json:"durationMinutes"`
	BlockedTargets  []string `json:"blockedTargets"`
}

type FocusSessionResponse struct {
	ID              string    `json:"id"`
	DurationMinutes int       `json:"durationMinutes"`
	RemainingSeconds int      `json:"remainingSeconds"`
	IsActive        bool      `json:"isActive"`
	StartedAt       time.Time `json:"startedAt"`
	EndsAt          time.Time `json:"endsAt"`
	BlockedTargets  []string  `json:"blockedTargets"`
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

func (h *Handler) StartFocus(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var req StartFocusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Invalid request payload"}`, http.StatusBadRequest)
		return
	}

	if req.DurationMinutes <= 0 {
		req.DurationMinutes = 45 // Default 45m
	}

	sessionID := uuid.New().String()
	now := time.Now().UTC()
	endsAt := now.Add(time.Duration(req.DurationMinutes) * time.Minute)

	if h.db != nil {
		q := `INSERT INTO focus_sessions (id, user_id, duration_minutes, is_completed, started_at, ended_at)
		      VALUES ($1, $2, $3, 0, $4, $5)`
		_, err := h.db.ExecContext(r.Context(), q, sessionID, claims.UserID.String(), req.DurationMinutes, now, endsAt)
		if err != nil {
			logger.Error("Failed to record focus session in DB", "error", err)
		}
	}

	resp := FocusSessionResponse{
		ID:               sessionID,
		DurationMinutes:  req.DurationMinutes,
		RemainingSeconds: req.DurationMinutes * 60,
		IsActive:         true,
		StartedAt:        now,
		EndsAt:           endsAt,
		BlockedTargets:   req.BlockedTargets,
	}

	// Broadcast across all connected user devices via WebSocket
	if h.wsHub != nil {
		h.wsHub.BroadcastToUser(claims.UserID, events.EventMessage{
			Event:   "FOCUS_STARTED",
			Payload: resp,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *Handler) EndFocus(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	now := time.Now().UTC()
	if h.db != nil {
		q := `UPDATE focus_sessions SET is_completed = 1, ended_at = $1 WHERE user_id = $2 AND is_completed = 0`
		_, err := h.db.ExecContext(r.Context(), q, now, claims.UserID.String())
		if err != nil {
			logger.Error("Failed to update focus session in DB", "error", err)
		}
	}

	if h.wsHub != nil {
		h.wsHub.BroadcastToUser(claims.UserID, events.EventMessage{
			Event: "FOCUS_ENDED",
			Payload: map[string]interface{}{
				"endedAt": now.Unix(),
			},
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "FOCUS_ENDED",
		"endedAt": now,
	})
}
