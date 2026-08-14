package devices

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/internal/middleware"
	"github.com/focusguard/focusguard/backend/pkg/logger"
)

type Handler struct {
	db *sql.DB
}

func NewHandler(db *sql.DB) *Handler {
	return &Handler{db: db}
}

func (h *Handler) RegisterDevice(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var req RegisterDeviceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Invalid request payload"}`, http.StatusBadRequest)
		return
	}

	if req.DeviceName == "" {
		req.DeviceName = "MacBook Pro"
	}
	if req.Platform == "" {
		req.Platform = PlatformMacOS
	}

	device := Device{
		ID:         uuid.New(),
		UserID:     claims.UserID,
		DeviceName: req.DeviceName,
		Platform:   req.Platform,
		OSVersion:  req.OSVersion,
		Status:     StatusOnline,
		LastSeenAt: time.Now().UTC(),
		CreatedAt:  time.Now().UTC(),
	}

	if h.db != nil {
		query := `INSERT INTO devices (id, user_id, device_name, platform, os_version, status, last_seen_at, created_at)
		          VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`
		_, err := h.db.ExecContext(r.Context(), query, device.ID.String(), device.UserID.String(), device.DeviceName,
			string(device.Platform), device.OSVersion, string(device.Status), device.LastSeenAt, device.CreatedAt)
		if err != nil {
			logger.Error("Failed to register device in DB", "error", err)
			http.Error(w, `{"error":"Database error"}`, http.StatusInternalServerError)
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(device)
}

func (h *Handler) ListDevices(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	devicesList := []Device{}

	if h.db != nil {
		query := `SELECT id, user_id, device_name, platform, os_version, status, last_seen_at, created_at
		          FROM devices WHERE user_id = $1 ORDER BY created_at DESC`
		rows, err := h.db.QueryContext(r.Context(), query, claims.UserID.String())
		if err != nil {
			logger.Error("Failed to query devices", "error", err)
			http.Error(w, `{"error":"Database query error"}`, http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		for rows.Next() {
			var idStr, userIDStr, platStr, statStr string
			var d Device
			if err := rows.Scan(&idStr, &userIDStr, &d.DeviceName, &platStr, &d.OSVersion, &statStr, &d.LastSeenAt, &d.CreatedAt); err != nil {
				logger.Error("Failed to scan device row", "error", err)
				continue
			}
			d.ID, _ = uuid.Parse(idStr)
			d.UserID, _ = uuid.Parse(userIDStr)
			d.Platform = PlatformType(platStr)
			d.Status = DeviceStatus(statStr)
			devicesList = append(devicesList, d)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(devicesList)
}
