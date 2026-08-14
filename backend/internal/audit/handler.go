package audit

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"time"

	"github.com/focusguard/focusguard/backend/internal/middleware"
)

type AuditLogEntry struct {
	ID        string    `json:"id"`
	UserID    string    `json:"userId"`
	DeviceID  *string   `json:"deviceId,omitempty"`
	Action    string    `json:"action"`
	Details   string    `json:"details"`
	Timestamp time.Time `json:"timestamp"`
}

type Handler struct {
	db *sql.DB
}

func NewHandler(db *sql.DB) *Handler {
	return &Handler{db: db}
}

func (h *Handler) GetAuditLogs(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	logsList := []AuditLogEntry{}
	if h.db != nil {
		q := `SELECT id, user_id, device_id, action, details, timestamp
		      FROM audit_logs
		      WHERE user_id = $1
		      ORDER BY timestamp DESC
		      LIMIT 50`
		rows, err := h.db.QueryContext(r.Context(), q, claims.UserID.String())
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var l AuditLogEntry
				var devID sql.NullString
				var details sql.NullString
				if err := rows.Scan(&l.ID, &l.UserID, &devID, &l.Action, &details, &l.Timestamp); err == nil {
					if devID.Valid {
						l.DeviceID = &devID.String
					}
					if details.Valid {
						l.Details = details.String
					}
					logsList = append(logsList, l)
				}
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(logsList)
}
