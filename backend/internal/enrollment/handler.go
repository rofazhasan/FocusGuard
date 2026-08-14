package enrollment

import (
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/internal/auth"
	"github.com/focusguard/focusguard/backend/internal/events"
	"github.com/focusguard/focusguard/backend/internal/middleware"
	"github.com/focusguard/focusguard/backend/pkg/logger"
)

type CreateEnrollmentRequest struct {
	DeviceName string `json:"deviceName"`
	TargetRole string `json:"targetRole"` // "PERSONAL", "MANAGED_USER"
}

type CreateEnrollmentResponse struct {
	ID          string    `json:"id"`
	PairingCode string    `json:"pairingCode"`
	DeviceName  string    `json:"deviceName"`
	TargetRole  string    `json:"targetRole"`
	ExpiresAt   time.Time `json:"expiresAt"`
	ExpiresInSec int      `json:"expiresInSec"`
	QRCodeURL   string    `json:"qrCodeUrl"`
}

type ClaimEnrollmentRequest struct {
	PairingCode string `json:"pairingCode"`
	DeviceName  string `json:"deviceName"`
	Platform    string `json:"platform"` // "MACOS", "ANDROID"
	OSVersion   string `json:"osVersion"`
}

type ClaimEnrollmentResponse struct {
	DeviceID      string         `json:"deviceId"`
	UserID        string         `json:"userId"`
	DeviceName    string         `json:"deviceName"`
	Platform      string         `json:"platform"`
	Role          string         `json:"role"`
	IsManaged     bool           `json:"isManaged"`
	PolicyVersion int            `json:"policyVersion"`
	AccessToken   string         `json:"accessToken"`
	Status        string         `json:"status"`
}

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

func (h *Handler) CreateEnrollment(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var req CreateEnrollmentRequest
	_ = json.NewDecoder(r.Body).Decode(&req)

	if req.DeviceName == "" {
		req.DeviceName = "Managed Device"
	}
	if req.TargetRole == "" {
		req.TargetRole = "MANAGED_USER"
	}

	pairingCode := generatePairingCode()
	tokenID := uuid.New().String()
	now := time.Now().UTC()
	expiresAt := now.Add(5 * time.Minute)

	if h.db != nil {
		q := `INSERT INTO enrollment_tokens (id, user_id, pairing_code, device_name, target_role, expires_at, is_claimed, created_at)
		      VALUES ($1, $2, $3, $4, $5, $6, 0, $7)`
		_, err := h.db.ExecContext(r.Context(), q, tokenID, claims.UserID.String(), pairingCode, req.DeviceName, req.TargetRole, expiresAt, now)
		if err != nil {
			logger.Error("Failed to store enrollment token", "error", err)
			http.Error(w, `{"error":"Database error creating enrollment code"}`, http.StatusInternalServerError)
			return
		}

		// Log audit event
		auditQ := `INSERT INTO audit_logs (id, user_id, action, details, timestamp)
		          VALUES ($1, $2, 'ENROLLMENT_TOKEN_CREATED', $3, CURRENT_TIMESTAMP)`
		_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), claims.UserID.String(), fmt.Sprintf("Created pairing code %s for %s", pairingCode, req.DeviceName))
	}

	resp := CreateEnrollmentResponse{
		ID:           tokenID,
		PairingCode:  pairingCode,
		DeviceName:   req.DeviceName,
		TargetRole:   req.TargetRole,
		ExpiresAt:    expiresAt,
		ExpiresInSec: 300,
		QRCodeURL:    fmt.Sprintf("focusguard://enroll?code=%s&owner=%s", pairingCode, claims.Email),
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *Handler) ClaimEnrollment(w http.ResponseWriter, r *http.Request) {
	var req ClaimEnrollmentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Invalid payload"}`, http.StatusBadRequest)
		return
	}

	cleanCode := strings.TrimSpace(strings.ToUpper(req.PairingCode))
	if cleanCode == "" {
		http.Error(w, `{"error":"Pairing code required"}`, http.StatusBadRequest)
		return
	}

	if h.db == nil {
		http.Error(w, `{"error":"Database unavailable"}`, http.StatusInternalServerError)
		return
	}

	// 1. Verify pairing code validity and TTL
	var tokenID, userIDStr, plannedDeviceName, targetRole string
	var expiresAt time.Time
	var isClaimedInt int

	q := `SELECT id, user_id, device_name, target_role, expires_at, is_claimed
	      FROM enrollment_tokens
	      WHERE pairing_code = $1`
	err := h.db.QueryRowContext(r.Context(), q, cleanCode).Scan(&tokenID, &userIDStr, &plannedDeviceName, &targetRole, &expiresAt, &isClaimedInt)
	if err == sql.ErrNoRows {
		http.Error(w, `{"error":"Invalid pairing code"}`, http.StatusNotFound)
		return
	} else if err != nil {
		logger.Error("Enrollment query error", "error", err)
		http.Error(w, `{"error":"Internal error"}`, http.StatusInternalServerError)
		return
	}

	if isClaimedInt == 1 {
		http.Error(w, `{"error":"Pairing code already claimed"}`, http.StatusGone)
		return
	}

	if time.Now().UTC().After(expiresAt) {
		http.Error(w, `{"error":"Pairing code has expired. Please request a new code from account owner."}`, http.StatusGone)
		return
	}

	// 2. Mark token as claimed
	_, _ = h.db.ExecContext(r.Context(), `UPDATE enrollment_tokens SET is_claimed = 1 WHERE id = $1`, tokenID)

	// 3. Create enrolled device
	deviceID := uuid.New()
	userID, _ := uuid.Parse(userIDStr)
	deviceName := req.DeviceName
	if deviceName == "" {
		deviceName = plannedDeviceName
	}
	platform := req.Platform
	if platform == "" {
		platform = "ANDROID"
	}
	osVer := req.OSVersion
	if osVer == "" {
		osVer = "Android 15 (API 35)"
	}
	isManaged := (targetRole == "MANAGED_USER")

	insertDevQ := `INSERT INTO devices (id, user_id, device_name, platform, os_version, role, is_managed, status, policy_version, last_seen_at, created_at)
	               VALUES ($1, $2, $3, $4, $5, $6, $7, 'ONLINE', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`
	managedInt := 0
	if isManaged {
		managedInt = 1
	}
	_, err = h.db.ExecContext(r.Context(), insertDevQ, deviceID.String(), userID.String(), deviceName, platform, osVer, targetRole, managedInt)
	if err != nil {
		logger.Error("Failed to register claimed device", "error", err)
		http.Error(w, `{"error":"Failed to enroll device"}`, http.StatusInternalServerError)
		return
	}

	// 4. Generate device access token
	token, _, err := h.tokenService.GenerateTokens(userID, fmt.Sprintf("device-%s@focusguard.local", deviceID.String()[:8]))
	if err != nil {
		logger.Error("Failed to generate device token", "error", err)
		http.Error(w, `{"error":"Token error"}`, http.StatusInternalServerError)
		return
	}

	// 5. Broadcast DEVICE_ENROLLED event to Owner via WebSocket
	if h.wsHub != nil {
		h.wsHub.BroadcastToUser(userID, events.EventMessage{
			Event: "DEVICE_ENROLLED",
			Payload: map[string]interface{}{
				"deviceId":   deviceID.String(),
				"deviceName": deviceName,
				"platform":   platform,
				"role":       targetRole,
				"isManaged":  isManaged,
				"status":     "ONLINE",
			},
		})
	}

	// Log audit event
	auditQ := `INSERT INTO audit_logs (id, user_id, device_id, action, details, timestamp)
	          VALUES ($1, $2, $3, 'DEVICE_ENROLLED_SUCCESS', $4, CURRENT_TIMESTAMP)`
	_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), userID.String(), deviceID.String(), fmt.Sprintf("Enrolled %s (%s) with role %s", deviceName, platform, targetRole))

	resp := ClaimEnrollmentResponse{
		DeviceID:      deviceID.String(),
		UserID:        userID.String(),
		DeviceName:    deviceName,
		Platform:      platform,
		Role:          targetRole,
		IsManaged:     isManaged,
		PolicyVersion: 1,
		AccessToken:   token,
		Status:        "ENROLLED_PROTECTED",
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *Handler) ListPendingEnrollments(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	tokensList := []CreateEnrollmentResponse{}
	if h.db != nil {
		q := `SELECT id, pairing_code, device_name, target_role, expires_at
		      FROM enrollment_tokens
		      WHERE user_id = $1 AND is_claimed = 0 AND expires_at > CURRENT_TIMESTAMP
		      ORDER BY created_at DESC`
		rows, err := h.db.QueryContext(r.Context(), q, claims.UserID.String())
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var t CreateEnrollmentResponse
				if err := rows.Scan(&t.ID, &t.PairingCode, &t.DeviceName, &t.TargetRole, &t.ExpiresAt); err == nil {
					t.ExpiresInSec = int(time.Until(t.ExpiresAt).Seconds())
					tokensList = append(tokensList, t)
				}
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(tokensList)
}

func generatePairingCode() string {
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	b := make([]byte, 6)
	for i := 0; i < 6; i++ {
		num, _ := rand.Int(rand.Reader, big.NewInt(int64(len(chars))))
		b[i] = chars[num.Int64()]
	}
	return fmt.Sprintf("FG-%s", string(b))
}
