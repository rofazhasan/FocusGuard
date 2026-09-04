package devices

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/internal/auth"
	"github.com/focusguard/focusguard/backend/internal/events"
	"github.com/focusguard/focusguard/backend/pkg/apierror"
	"github.com/focusguard/focusguard/backend/pkg/logger"
	"github.com/focusguard/focusguard/backend/pkg/requestid"
)

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

func (h *Handler) RegisterDevice(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())
	claims, ok := auth.GetUserClaims(r.Context())
	if !ok {
		apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Unauthorized", reqID)
		return
	}

	var req RegisterDeviceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Invalid request payload", reqID)
		return
	}

	if req.DeviceName == "" {
		req.DeviceName = "MacBook Pro"
	}
	if req.Platform == "" {
		req.Platform = PlatformMacOS
	}
	if req.ClientType == "" {
		req.ClientType = ClientExtension
	}
	if req.AppVersion == "" {
		req.AppVersion = "1.0.0"
	}

	now := time.Now().UTC()
	device := Device{
		ID:              uuid.New(),
		UserID:          claims.UserID,
		DeviceName:      req.DeviceName,
		Platform:        req.Platform,
		ClientType:      req.ClientType,
		OSVersion:       req.OSVersion,
		AppVersion:      req.AppVersion,
		Status:          StatusActive,
		ProtectionState: "PROTECTED",
		PolicyVersion:   1,
		LastSeenAt:      now,
		CreatedAt:       now,
	}

	if h.db != nil {
		tx, err := h.db.BeginTx(r.Context(), nil)
		if err != nil {
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database error", reqID)
			return
		}
		defer tx.Rollback()

		query := `INSERT INTO devices (id, user_id, device_name, platform, client_type, os_version, app_version, status, protection_state, policy_version, last_seen_at, created_at)
		          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`
		_, err = tx.ExecContext(r.Context(), query, device.ID.String(), device.UserID.String(), device.DeviceName,
			string(device.Platform), string(device.ClientType), device.OSVersion, device.AppVersion,
			string(device.Status), device.ProtectionState, device.PolicyVersion, device.LastSeenAt, device.CreatedAt)
		if err != nil {
			logger.Error("Failed to register device in DB", "error", err)
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database error registering device", reqID)
			return
		}

		if req.PublicKey != "" {
			algo := req.KeyAlgorithm
			if algo == "" {
				algo = "Ed25519"
			}
			pkQ := `INSERT INTO device_public_identities (id, device_id, public_key, key_algorithm, created_at)
			        VALUES ($1, $2, $3, $4, $5)`
			_, _ = tx.ExecContext(r.Context(), pkQ, uuid.New().String(), device.ID.String(), req.PublicKey, algo, now)
		}

		// Initial Sync Cursor
		scQ := `INSERT INTO sync_cursors (id, device_id, last_policy_version, last_sync_at, updated_at)
		        VALUES ($1, $2, 1, $3, $4)`
		_, _ = tx.ExecContext(r.Context(), scQ, uuid.New().String(), device.ID.String(), now, now)

		// Audit Log
		auditQ := `INSERT INTO audit_logs (id, user_id, device_id, action, details, actor_type, actor_id, request_id, timestamp)
		          VALUES ($1, $2, $3, 'DEVICE_ENROLLED', $4, 'USER', $5, $6, CURRENT_TIMESTAMP)`
		_, _ = tx.ExecContext(r.Context(), auditQ, uuid.New().String(), claims.UserID.String(), device.ID.String(),
			"Enrolled device "+device.DeviceName+" ("+string(device.Platform)+")", claims.UserID.String(), reqID)

		if err := tx.Commit(); err != nil {
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Failed to commit device registration", reqID)
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(device)
}

func (h *Handler) ListDevices(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())
	claims, ok := auth.GetUserClaims(r.Context())
	if !ok {
		apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Unauthorized", reqID)
		return
	}

	devicesList := []Device{}

	if h.db != nil {
		query := `SELECT id, user_id, device_name, platform, client_type, os_version, app_version, status, protection_state, policy_version, last_seen_at, created_at, revoked_at
		          FROM devices WHERE user_id = $1 ORDER BY created_at DESC`
		rows, err := h.db.QueryContext(r.Context(), query, claims.UserID.String())
		if err != nil {
			logger.Error("Failed to query devices", "error", err)
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database query error", reqID)
			return
		}
		defer rows.Close()

		now := time.Now().UTC()
		for rows.Next() {
			var idStr, userIDStr, platStr, clientStr, statStr, protStr string
			var appVer, osVer sql.NullString
			var polVer int
			var lastSeen, createdAt time.Time
			var revokedAt sql.NullTime

			if err := rows.Scan(&idStr, &userIDStr, &statStr, &platStr, &clientStr, &osVer, &appVer, &statStr, &protStr, &polVer, &lastSeen, &createdAt, &revokedAt); err != nil {
				// Fallback scan for backward-compatible column set
				var d Device
				var idFallback, uidFallback, platFallback, statusFallback string
				if fErr := rows.Scan(&idFallback, &uidFallback, &d.DeviceName, &platFallback, &d.OSVersion, &statusFallback, &d.LastSeenAt, &d.CreatedAt); fErr == nil {
					d.ID, _ = uuid.Parse(idFallback)
					d.UserID, _ = uuid.Parse(uidFallback)
					d.Platform = PlatformType(platFallback)
					d.Status = DeviceStatus(statusFallback)
					d.ProtectionState = "PROTECTED"
					d.PolicyVersion = 1
					devicesList = append(devicesList, d)
				}
				continue
			}

			d := Device{
				DeviceName:      statStr, // scanned into name position
				Platform:        PlatformType(platStr),
				ClientType:      ClientType(clientStr),
				OSVersion:       osVer.String,
				AppVersion:      appVer.String,
				Status:          DeviceStatus(statStr),
				ProtectionState: protStr,
				PolicyVersion:   polVer,
				LastSeenAt:      lastSeen,
				CreatedAt:       createdAt,
			}
			d.ID, _ = uuid.Parse(idStr)
			d.UserID, _ = uuid.Parse(userIDStr)

			if revokedAt.Valid {
				t := revokedAt.Time
				d.RevokedAt = &t
				d.Status = StatusRevoked
			} else if d.Status != StatusRevoked && now.Sub(lastSeen) > 3*time.Minute {
				// Dynamic offline evaluation
				d.Status = StatusOffline
			}

			devicesList = append(devicesList, d)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(devicesList)
}

func (h *Handler) Heartbeat(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())
	deviceIDStr := chi.URLParam(r, "id")
	if deviceIDStr == "" {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Device ID required", reqID)
		return
	}

	var req HeartbeatRequest
	_ = json.NewDecoder(r.Body).Decode(&req)

	now := time.Now().UTC()
	var currentStatus string
	var policyVersion int

	if h.db != nil {
		q := `SELECT status, policy_version FROM devices WHERE id = $1`
		err := h.db.QueryRowContext(r.Context(), q, deviceIDStr).Scan(&currentStatus, &policyVersion)
		if err == sql.ErrNoRows {
			apierror.Write(w, http.StatusNotFound, apierror.CodeDeviceNotFound, "Device not found", reqID)
			return
		} else if err != nil {
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database error", reqID)
			return
		}

		if strings.ToUpper(currentStatus) == "REVOKED" {
			apierror.Write(w, http.StatusForbidden, apierror.CodeDeviceRevoked, "Device is permanently revoked", reqID)
			return
		}

		// Update heartbeat in DB
		updateQ := `UPDATE devices SET last_seen_at = $1, status = 'ACTIVE' WHERE id = $2`
		_, _ = h.db.ExecContext(r.Context(), updateQ, now, deviceIDStr)
	} else {
		currentStatus = "ACTIVE"
		policyVersion = 1
	}

	resp := HeartbeatResponse{
		Acknowledged:        true,
		DeviceStatus:        DeviceStatus(currentStatus),
		LatestPolicyVersion: policyVersion,
		ServerTime:          now,
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *Handler) RevokeDevice(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())
	claims, ok := auth.GetUserClaims(r.Context())
	if !ok {
		apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Unauthorized", reqID)
		return
	}

	deviceIDStr := chi.URLParam(r, "id")
	if deviceIDStr == "" {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Device ID is required in URL", reqID)
		return
	}

	now := time.Now().UTC()

	if h.db != nil {
		var ownerUserIDStr string
		checkQ := `SELECT user_id FROM devices WHERE id = $1`
		err := h.db.QueryRowContext(r.Context(), checkQ, deviceIDStr).Scan(&ownerUserIDStr)
		if err == sql.ErrNoRows {
			apierror.Write(w, http.StatusNotFound, apierror.CodeDeviceNotFound, "Device not found", reqID)
			return
		} else if err != nil {
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database query error", reqID)
			return
		}

		if ownerUserIDStr != claims.UserID.String() {
			apierror.Write(w, http.StatusForbidden, apierror.CodeAuthInvalid, "Cannot revoke device belonging to another user", reqID)
			return
		}

		tx, err := h.db.BeginTx(r.Context(), nil)
		if err != nil {
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Transaction error", reqID)
			return
		}
		defer tx.Rollback()

		// 1. Mark device revoked
		_, err = tx.ExecContext(r.Context(), `UPDATE devices SET status = 'REVOKED', revoked_at = $1 WHERE id = $2`, now, deviceIDStr)
		if err != nil {
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Failed to revoke device", reqID)
			return
		}

		// 2. Invalidate all device credentials
		_, _ = tx.ExecContext(r.Context(), `UPDATE device_credentials SET revoked_at = $1 WHERE device_id = $2`, now, deviceIDStr)

		// 3. Log Audit event
		auditQ := `INSERT INTO audit_logs (id, user_id, device_id, action, details, actor_type, actor_id, request_id, timestamp)
		          VALUES ($1, $2, $3, 'DEVICE_REVOKED', 'Owner revoked device authorization', 'USER', $4, $5, CURRENT_TIMESTAMP)`
		_, _ = tx.ExecContext(r.Context(), auditQ, uuid.New().String(), claims.UserID.String(), deviceIDStr, claims.UserID.String(), reqID)

		if err := tx.Commit(); err != nil {
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Failed to commit revocation", reqID)
			return
		}
	}

	// 4. Notify and teardown WebSocket connections
	if h.wsHub != nil {
		h.wsHub.BroadcastToUser(claims.UserID, events.EventMessage{
			Event: "DEVICE_REVOKED",
			Payload: map[string]interface{}{
				"deviceId":  deviceIDStr,
				"status":    "REVOKED",
				"revokedAt": now.Format(time.RFC3339),
			},
		})
	}

	resp := RevokeDeviceResponse{
		Success:   true,
		DeviceID:  deviceIDStr,
		Status:    "REVOKED",
		RevokedAt: now,
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}
