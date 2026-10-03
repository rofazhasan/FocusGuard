package pairing

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
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
	db           *sql.DB
	tokenService *auth.TokenService
	wsHub        *events.Hub
}

func NewHandler(db *sql.DB, tokenService *auth.TokenService, wsHub *events.Hub) *Handler {
	return &Handler{
		db:           db,
		tokenService: tokenService,
		wsHub:        wsHub,
	}
}

func normalizePairingCode(code string) string {
	clean := strings.ToUpper(strings.TrimSpace(code))
	clean = strings.ReplaceAll(clean, " ", "")
	clean = strings.ReplaceAll(clean, "_", "")
	if strings.HasPrefix(clean, "FG-") {
		return clean
	}
	if strings.HasPrefix(clean, "FG") {
		return "FG-" + strings.TrimPrefix(clean, "FG")
	}
	if len(clean) > 0 {
		return "FG-" + clean
	}
	return clean
}

func hashCode(code string) string {
	canonical := normalizePairingCode(code)
	sum := sha256.Sum256([]byte(canonical))
	return hex.EncodeToString(sum[:])
}

func generateHumanCode() string {
	const chars = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
	b := make([]byte, 6)
	for i := 0; i < 6; i++ {
		num, _ := rand.Int(rand.Reader, big.NewInt(int64(len(chars))))
		b[i] = chars[num.Int64()]
	}
	return fmt.Sprintf("FG-%s", string(b))
}

// 1. Create Pairing Session (Authenticated Owner)
func (h *Handler) CreateSession(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())
	claims, ok := auth.GetUserClaims(r.Context())
	if !ok {
		apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Unauthorized", reqID)
		return
	}

	sessionID := uuid.New()
	code := generateHumanCode()
	codeHash := hashCode(code)
	now := time.Now().UTC()
	expiresAt := now.Add(5 * time.Minute)

	if h.db != nil {
		q := `INSERT INTO pairing_sessions (id, owner_user_id, code_hash, status, expires_at, created_at)
		      VALUES ($1, $2, $3, 'CREATED', $4, $5)`
		_, err := h.db.ExecContext(r.Context(), q, sessionID.String(), claims.UserID.String(), codeHash, expiresAt, now)
		if err != nil {
			logger.Error("Failed to create pairing session in DB", "error", err)
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Failed to create pairing session", reqID)
			return
		}

		// Log audit event
		auditQ := `INSERT INTO audit_logs (id, user_id, action, details, actor_type, actor_id, request_id, timestamp)
		          VALUES ($1, $2, 'DEVICE_PAIRING_CREATED', $3, 'USER', $4, $5, CURRENT_TIMESTAMP)`
		_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), claims.UserID.String(),
			"Created pairing session "+sessionID.String(), claims.UserID.String(), reqID)
	}

	resp := CreateSessionResponse{
		SessionID:    sessionID,
		PairingCode:  code,
		QRPayload:    fmt.Sprintf("focusguard://pair?session=%s", sessionID.String()),
		Status:       StatusCreated,
		ExpiresAt:    expiresAt,
		ExpiresInSec: 300,
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(resp)
}

// 2. Get Pairing Session Details
func (h *Handler) GetSession(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())
	sessionIDStr := chi.URLParam(r, "id")
	sessionID, err := uuid.Parse(sessionIDStr)
	if err != nil {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Invalid session ID format", reqID)
		return
	}

	var detail PairingSessionDetail
	if h.db != nil {
		var ownerIDStr, statusStr string
		var rawMeta sql.NullString
		var enrolledDevID sql.NullString
		var expiresAt, createdAt time.Time

		q := `SELECT id, owner_user_id, status, requested_device_metadata, enrolled_device_id, expires_at, created_at
		      FROM pairing_sessions WHERE id = $1`
		err := h.db.QueryRowContext(r.Context(), q, sessionID.String()).Scan(&sessionIDStr, &ownerIDStr, &statusStr, &rawMeta, &enrolledDevID, &expiresAt, &createdAt)
		if err == sql.ErrNoRows {
			apierror.Write(w, http.StatusNotFound, apierror.CodePairingNotFound, "Pairing session not found", reqID)
			return
		} else if err != nil {
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database error", reqID)
			return
		}

		detail.SessionID = sessionID
		detail.OwnerUserID, _ = uuid.Parse(ownerIDStr)
		detail.Status = SessionStatus(statusStr)
		detail.ExpiresAt = expiresAt
		detail.ExpiresInSec = int(time.Until(expiresAt).Seconds())
		detail.CreatedAt = createdAt

		if detail.ExpiresInSec <= 0 && detail.Status == StatusCreated {
			detail.Status = StatusExpired
		}

		if rawMeta.Valid && rawMeta.String != "" {
			var meta map[string]interface{}
			_ = json.Unmarshal([]byte(rawMeta.String), &meta)
			detail.RequestedDeviceMetadata = meta
		}

		if enrolledDevID.Valid && enrolledDevID.String != "" {
			dID, _ := uuid.Parse(enrolledDevID.String)
			detail.EnrolledDeviceID = &dID
		}
	} else {
		detail.SessionID = sessionID
		detail.Status = StatusCreated
		detail.ExpiresInSec = 300
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(detail)
}

// 3. New Client Requests Pairing (Unauthenticated device submit)
func (h *Handler) SubmitRequest(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())
	sessionIDStr := chi.URLParam(r, "id")

	var req EnrollmentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Invalid request payload", reqID)
		return
	}

	if req.DeviceName == "" {
		req.DeviceName = "New Device"
	}
	if req.Platform == "" {
		req.Platform = "BROWSER"
	}
	if req.ClientType == "" {
		req.ClientType = "EXTENSION"
	}
	if req.AppVersion == "" {
		req.AppVersion = "1.0.0"
	}

	if h.db == nil {
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database unavailable", reqID)
		return
	}

	// Lookup session by ID or Pairing Code
	var sessionID, ownerIDStr, currentStatus string
	var expiresAt time.Time

	if sessionIDStr != "" && sessionIDStr != ":id" {
		q := `SELECT id, owner_user_id, status, expires_at FROM pairing_sessions WHERE id = $1`
		err := h.db.QueryRowContext(r.Context(), q, sessionIDStr).Scan(&sessionID, &ownerIDStr, &currentStatus, &expiresAt)
		if err == sql.ErrNoRows {
			apierror.Write(w, http.StatusNotFound, apierror.CodePairingNotFound, "Pairing session not found", reqID)
			return
		} else if err != nil {
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database query error", reqID)
			return
		}
	} else if req.PairingCode != "" {
		codeHash := hashCode(req.PairingCode)
		q := `SELECT id, owner_user_id, status, expires_at FROM pairing_sessions WHERE code_hash = $1`
		err := h.db.QueryRowContext(r.Context(), q, codeHash).Scan(&sessionID, &ownerIDStr, &currentStatus, &expiresAt)
		if err == sql.ErrNoRows {
			apierror.Write(w, http.StatusNotFound, apierror.CodePairingNotFound, "Invalid pairing code", reqID)
			return
		} else if err != nil {
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database query error", reqID)
			return
		}
	} else {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Session ID or PairingCode required", reqID)
		return
	}

	// Validate status and expiry
	if time.Now().UTC().After(expiresAt) {
		_, _ = h.db.ExecContext(r.Context(), `UPDATE pairing_sessions SET status = 'EXPIRED' WHERE id = $1`, sessionID)
		apierror.Write(w, http.StatusGone, apierror.CodePairingExpired, "Pairing session has expired", reqID)
		return
	}

	if currentStatus == "CONSUMED" {
		apierror.Write(w, http.StatusGone, apierror.CodePairingConsumed, "Pairing session has already been consumed", reqID)
		return
	}

	if currentStatus != "CREATED" && currentStatus != "SCANNED" && currentStatus != "PENDING_APPROVAL" {
		apierror.Write(w, http.StatusConflict, apierror.CodePairingInvalidState, "Pairing session is in invalid state: "+currentStatus, reqID)
		return
	}

	// Save requested metadata
	metaMap := map[string]interface{}{
		"deviceName":   req.DeviceName,
		"platform":     req.Platform,
		"clientType":   req.ClientType,
		"appVersion":   req.AppVersion,
		"keyAlgorithm": req.KeyAlgorithm,
		"requestedAt":  time.Now().UTC().Format(time.RFC3339),
	}
	metaJSON, _ := json.Marshal(metaMap)

	updateQ := `UPDATE pairing_sessions
	            SET status = 'PENDING_APPROVAL', requested_device_metadata = $1, requested_public_key = $2
	            WHERE id = $3`
	_, err := h.db.ExecContext(r.Context(), updateQ, string(metaJSON), req.PublicKey, sessionID)
	if err != nil {
		logger.Error("Failed to update pairing session status", "error", err)
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database update error", reqID)
		return
	}

	// Log audit event
	auditQ := `INSERT INTO audit_logs (id, user_id, action, details, actor_type, actor_id, request_id, timestamp)
	          VALUES ($1, $2, 'PAIRING_REQUESTED', $3, 'DEVICE', $4, $5, CURRENT_TIMESTAMP)`
	_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), ownerIDStr,
		"Device "+req.DeviceName+" requested enrollment", req.DeviceName, reqID)

	// Broadcast PAIRING_REQUEST_RECEIVED over WebSocket to Owner Dashboard
	if h.wsHub != nil {
		if ownerUUID, err := uuid.Parse(ownerIDStr); err == nil {
			h.wsHub.BroadcastToUser(ownerUUID, events.EventMessage{
				Event: "PAIRING_REQUEST_RECEIVED",
				Payload: map[string]interface{}{
					"sessionId":  sessionID,
					"deviceName": req.DeviceName,
					"platform":   req.Platform,
					"clientType": req.ClientType,
					"appVersion": req.AppVersion,
					"publicKey":  req.PublicKey,
					"timestamp":  time.Now().UTC().Format(time.RFC3339),
				},
			})
		}
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"sessionId": sessionID,
		"status":    StatusPendingApproval,
		"message":   "Pairing request submitted. Waiting for owner approval on dashboard.",
	})
}

// 4. Owner Explicitly Approves Enrollment (Authenticated Owner, Atomic Transaction)
func (h *Handler) ApproveRequest(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())
	claims, ok := auth.GetUserClaims(r.Context())
	if !ok {
		apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Unauthorized", reqID)
		return
	}

	sessionIDStr := chi.URLParam(r, "id")
	if sessionIDStr == "" {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Session ID required", reqID)
		return
	}

	if h.db == nil {
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database unavailable", reqID)
		return
	}

	tx, err := h.db.BeginTx(r.Context(), nil)
	if err != nil {
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Transaction error", reqID)
		return
	}
	defer tx.Rollback()

	// 1. Verify session state, ownership, and expiry
	var ownerIDStr, currentStatus, rawMeta sql.NullString
	var pubKey sql.NullString
	var expiresAt time.Time

	q := `SELECT owner_user_id, status, requested_device_metadata, requested_public_key, expires_at
	      FROM pairing_sessions WHERE id = $1`
	err = tx.QueryRowContext(r.Context(), q, sessionIDStr).Scan(&ownerIDStr, &currentStatus, &rawMeta, &pubKey, &expiresAt)
	if err == sql.ErrNoRows {
		apierror.Write(w, http.StatusNotFound, apierror.CodePairingNotFound, "Pairing session not found", reqID)
		return
	} else if err != nil {
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database error", reqID)
		return
	}

	if ownerIDStr.String != claims.UserID.String() {
		apierror.Write(w, http.StatusForbidden, apierror.CodePairingUnauthorized, "Cannot approve pairing session belonging to another user", reqID)
		return
	}

	if time.Now().UTC().After(expiresAt) {
		apierror.Write(w, http.StatusGone, apierror.CodePairingExpired, "Pairing session has expired", reqID)
		return
	}

	if currentStatus.String == "APPROVED" || currentStatus.String == "CONSUMED" {
		// Idempotent safe return
		w.Header().Set("Content-Type", "application/json")
		if reqID != "" {
			w.Header().Set("X-Request-ID", reqID)
		}
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"status": "APPROVED", "message": "Already approved"})
		return
	}

	if currentStatus.String != "PENDING_APPROVAL" {
		apierror.Write(w, http.StatusConflict, apierror.CodePairingInvalidState, "Pairing session is not pending approval (status: "+currentStatus.String+")", reqID)
		return
	}

	// Parse metadata
	var meta map[string]interface{}
	if rawMeta.Valid {
		_ = json.Unmarshal([]byte(rawMeta.String), &meta)
	}

	deviceName, _ := meta["deviceName"].(string)
	if deviceName == "" {
		deviceName = "FocusGuard Device"
	}
	platform, _ := meta["platform"].(string)
	if platform == "" {
		platform = "BROWSER"
	}
	clientType, _ := meta["clientType"].(string)
	if clientType == "" {
		clientType = "EXTENSION"
	}
	appVersion, _ := meta["appVersion"].(string)
	if appVersion == "" {
		appVersion = "1.0.0"
	}

	deviceID := uuid.New()
	now := time.Now().UTC()

	// 2. Create Active Device Record
	devQ := `INSERT INTO devices (id, user_id, device_name, platform, client_type, os_version, app_version, status, protection_state, policy_version, last_seen_at, created_at)
	         VALUES ($1, $2, $3, $4, $5, $6, $7, 'ACTIVE', 'PROTECTED', 1, $8, $9)`
	_, err = tx.ExecContext(r.Context(), devQ, deviceID.String(), claims.UserID.String(), deviceName,
		platform, clientType, "Managed Client", appVersion, now, now)
	if err != nil {
		logger.Error("Failed to insert device record in pairing approval", "error", err)
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Failed to create device record", reqID)
		return
	}

	// 3. Store Public Key if provided
	if pubKey.Valid && pubKey.String != "" {
		pkQ := `INSERT INTO device_public_identities (id, device_id, public_key, key_algorithm, created_at)
		        VALUES ($1, $2, $3, 'Ed25519', $4)`
		_, _ = tx.ExecContext(r.Context(), pkQ, uuid.New().String(), deviceID.String(), pubKey.String, now)
	}

	// 4. Create Device Credential Record
	credQ := `INSERT INTO device_credentials (id, device_id, credential_hash, credential_version, expires_at, created_at, last_used_at)
	          VALUES ($1, $2, $3, 1, $4, $5, $6)`
	_, err = tx.ExecContext(r.Context(), credQ, uuid.New().String(), deviceID.String(), "v1_credential_active",
		now.Add(30*24*time.Hour), now, now)
	if err != nil {
		logger.Error("Failed to insert device credential", "error", err)
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Credential error", reqID)
		return
	}

	// 5. Initialize Sync Cursor
	scQ := `INSERT INTO sync_cursors (id, device_id, last_policy_version, last_sync_at, updated_at)
	        VALUES ($1, $2, 1, $3, $4)`
	_, _ = tx.ExecContext(r.Context(), scQ, uuid.New().String(), deviceID.String(), now, now)

	// 6. Mark Pairing Session APPROVED
	upSessionQ := `UPDATE pairing_sessions SET status = 'APPROVED', enrolled_device_id = $1 WHERE id = $2`
	_, err = tx.ExecContext(r.Context(), upSessionQ, deviceID.String(), sessionIDStr)
	if err != nil {
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Failed to update session status", reqID)
		return
	}

	// 7. Audit Log
	auditQ := `INSERT INTO audit_logs (id, user_id, device_id, action, details, actor_type, actor_id, request_id, timestamp)
	          VALUES ($1, $2, $3, 'PAIRING_APPROVED', $4, 'USER', $5, $6, CURRENT_TIMESTAMP)`
	_, _ = tx.ExecContext(r.Context(), auditQ, uuid.New().String(), claims.UserID.String(), deviceID.String(),
		"Approved enrollment for "+deviceName, claims.UserID.String(), reqID)

	if err := tx.Commit(); err != nil {
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Failed to commit pairing approval", reqID)
		return
	}

	// 8. Generate Device Token
	deviceToken, _ := h.tokenService.GenerateDeviceToken(deviceID, claims.UserID, 1)

	// 9. Real-time broadcast
	if h.wsHub != nil {
		h.wsHub.BroadcastToUser(claims.UserID, events.EventMessage{
			Event: "DEVICE_ENROLLED",
			Payload: map[string]interface{}{
				"deviceId":   deviceID.String(),
				"deviceName": deviceName,
				"platform":   platform,
				"status":     "ACTIVE",
			},
		})
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"status":      "APPROVED",
		"deviceId":    deviceID.String(),
		"deviceToken": deviceToken,
		"deviceName":  deviceName,
	})
}

// 5. Owner Rejects Enrollment
func (h *Handler) RejectRequest(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())
	claims, ok := auth.GetUserClaims(r.Context())
	if !ok {
		apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Unauthorized", reqID)
		return
	}

	sessionIDStr := chi.URLParam(r, "id")
	if sessionIDStr == "" {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Session ID required", reqID)
		return
	}

	if h.db != nil {
		_, _ = h.db.ExecContext(r.Context(), `UPDATE pairing_sessions SET status = 'REJECTED' WHERE id = $1 AND owner_user_id = $2`,
			sessionIDStr, claims.UserID.String())

		auditQ := `INSERT INTO audit_logs (id, user_id, action, details, actor_type, actor_id, request_id, timestamp)
		          VALUES ($1, $2, 'PAIRING_REJECTED', 'Owner rejected pairing session', 'USER', $3, $4, CURRENT_TIMESTAMP)`
		_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), claims.UserID.String(), claims.UserID.String(), reqID)
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"status": "REJECTED"})
}

// 6. Owner Cancels Pairing Session
func (h *Handler) CancelSession(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())
	claims, ok := auth.GetUserClaims(r.Context())
	if !ok {
		apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Unauthorized", reqID)
		return
	}

	sessionIDStr := chi.URLParam(r, "id")
	if sessionIDStr == "" {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Session ID required", reqID)
		return
	}

	if h.db != nil {
		_, _ = h.db.ExecContext(r.Context(), `UPDATE pairing_sessions SET status = 'CANCELLED' WHERE id = $1 AND owner_user_id = $2`,
			sessionIDStr, claims.UserID.String())
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"status": "CANCELLED"})
}

// 7. Device Polls Status
func (h *Handler) PollStatus(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())
	sessionIDStr := chi.URLParam(r, "id")

	if h.db == nil {
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database unavailable", reqID)
		return
	}

	var status, ownerIDStr string
	var enrolledDevID sql.NullString
	var expiresAt time.Time

	q := `SELECT status, owner_user_id, enrolled_device_id, expires_at FROM pairing_sessions WHERE id = $1`
	err := h.db.QueryRowContext(r.Context(), q, sessionIDStr).Scan(&status, &ownerIDStr, &enrolledDevID, &expiresAt)
	if err == sql.ErrNoRows {
		apierror.Write(w, http.StatusNotFound, apierror.CodePairingNotFound, "Pairing session not found", reqID)
		return
	} else if err != nil {
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database error", reqID)
		return
	}

	now := time.Now().UTC()
	if now.After(expiresAt) && status != "APPROVED" && status != "CONSUMED" {
		status = "EXPIRED"
	}

	resp := DeviceStatusPollResponse{
		Status:     SessionStatus(status),
		ServerTime: now,
	}

	if status == "APPROVED" && enrolledDevID.Valid {
		devUUID, _ := uuid.Parse(enrolledDevID.String)
		ownerUUID, _ := uuid.Parse(ownerIDStr)

		resp.DeviceID = devUUID.String()
		token, _ := h.tokenService.GenerateDeviceToken(devUUID, ownerUUID, 1)
		resp.DeviceToken = token

		// Once device fetches token, session transitions to CONSUMED
		_, _ = h.db.ExecContext(r.Context(), `UPDATE pairing_sessions SET status = 'CONSUMED', consumed_at = $1 WHERE id = $2`, now, sessionIDStr)
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}
