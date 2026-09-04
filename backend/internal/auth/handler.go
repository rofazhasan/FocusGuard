package auth

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/pkg/apierror"
	"github.com/focusguard/focusguard/backend/pkg/logger"
	"github.com/focusguard/focusguard/backend/pkg/requestid"
)

type Handler struct {
	db           *sql.DB
	tokenService *TokenService
}

func NewHandler(db *sql.DB, tokenService *TokenService) *Handler {
	return &Handler{
		db:           db,
		tokenService: tokenService,
	}
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())

	var req RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Invalid request payload", reqID)
		return
	}

	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if req.Email == "" || !strings.Contains(req.Email, "@") {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "A valid email address is required", reqID)
		return
	}

	if len(req.Password) < 8 {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Password must be at least 8 characters long", reqID)
		return
	}

	hash, err := HashPassword(req.Password)
	if err != nil {
		logger.Error("Failed to hash password with Argon2id", "error", err)
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Internal server error", reqID)
		return
	}

	userID := uuid.New()
	now := time.Now().UTC()

	if h.db != nil {
		query := `INSERT INTO users (id, email, password_hash, created_at, updated_at) VALUES ($1, $2, $3, $4, $5)`
		_, err = h.db.ExecContext(r.Context(), query, userID.String(), req.Email, hash, now, now)
		if err != nil {
			if strings.Contains(err.Error(), "duplicate key") || strings.Contains(err.Error(), "UNIQUE constraint") || strings.Contains(err.Error(), "unique constraint") {
				apierror.Write(w, http.StatusConflict, apierror.CodeValidationError, "User with this email already exists", reqID)
				return
			}
			logger.Error("Failed to insert user into DB", "error", err)
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Database error", reqID)
			return
		}

		// Log audit event
		auditQ := `INSERT INTO audit_logs (id, user_id, action, details, actor_type, actor_id, request_id, timestamp)
		          VALUES ($1, $2, 'USER_REGISTERED', 'User registered account', 'USER', $3, $4, CURRENT_TIMESTAMP)`
		_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), userID.String(), userID.String(), reqID)
	}

	access, refresh, err := h.tokenService.GenerateTokens(userID, req.Email)
	if err != nil {
		logger.Error("Failed to generate tokens", "error", err)
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Token generation error", reqID)
		return
	}

	// Store session in user_sessions
	if h.db != nil {
		sessQ := `INSERT INTO user_sessions (id, user_id, refresh_token_hash, user_agent, ip_address, expires_at, created_at, last_used_at)
		          VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`
		_, _ = h.db.ExecContext(r.Context(), sessQ, uuid.New().String(), userID.String(), hashToken(refresh),
			r.UserAgent(), r.RemoteAddr, now.Add(30*24*time.Hour), now, now)
	}

	resp := AuthResponse{
		AccessToken:  access,
		RefreshToken: refresh,
		User: UserDto{
			ID:    userID,
			Email: req.Email,
		},
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())

	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Invalid request payload", reqID)
		return
	}

	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if req.Email == "" || req.Password == "" {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Email and password are required", reqID)
		return
	}

	var userIDStr string
	var storedHash string

	if h.db != nil {
		query := `SELECT id, password_hash FROM users WHERE email = $1`
		err := h.db.QueryRowContext(r.Context(), query, req.Email).Scan(&userIDStr, &storedHash)
		if err == sql.ErrNoRows {
			// Record failed login audit
			auditQ := `INSERT INTO audit_logs (id, action, details, actor_type, actor_id, request_id, timestamp)
			          VALUES ($1, 'LOGIN_FAILED', $2, 'USER', $3, $4, CURRENT_TIMESTAMP)`
			_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), "Failed login attempt: non-existent email", req.Email, reqID)

			apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Invalid credentials", reqID)
			return
		} else if err != nil {
			logger.Error("Database query error on login", "error", err)
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Internal server error", reqID)
			return
		}

		if !CheckPasswordHash(req.Password, storedHash) {
			auditQ := `INSERT INTO audit_logs (id, user_id, action, details, actor_type, actor_id, request_id, timestamp)
			          VALUES ($1, $2, 'LOGIN_FAILED', 'Failed password verification', 'USER', $3, $4, CURRENT_TIMESTAMP)`
			_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), userIDStr, userIDStr, reqID)

			apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Invalid credentials", reqID)
			return
		}
	} else {
		userIDStr = uuid.New().String()
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		userID = uuid.New()
	}

	access, refresh, err := h.tokenService.GenerateTokens(userID, req.Email)
	if err != nil {
		logger.Error("Failed to generate tokens on login", "error", err)
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Internal token generation error", reqID)
		return
	}

	// Record session in user_sessions & log audit
	now := time.Now().UTC()
	if h.db != nil {
		sessQ := `INSERT INTO user_sessions (id, user_id, refresh_token_hash, user_agent, ip_address, expires_at, created_at, last_used_at)
		          VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`
		_, _ = h.db.ExecContext(r.Context(), sessQ, uuid.New().String(), userID.String(), hashToken(refresh),
			r.UserAgent(), r.RemoteAddr, now.Add(30*24*time.Hour), now, now)

		auditQ := `INSERT INTO audit_logs (id, user_id, action, details, actor_type, actor_id, request_id, timestamp)
		          VALUES ($1, $2, 'LOGIN_SUCCESS', 'Successful login', 'USER', $3, $4, CURRENT_TIMESTAMP)`
		_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), userID.String(), userID.String(), reqID)
	}

	resp := AuthResponse{
		AccessToken:  access,
		RefreshToken: refresh,
		User: UserDto{
			ID:    userID,
			Email: req.Email,
		},
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *Handler) Refresh(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())

	var req RefreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RefreshToken == "" {
		apierror.Write(w, http.StatusBadRequest, apierror.CodeValidationError, "Valid refreshToken required", reqID)
		return
	}

	claims, err := h.tokenService.ValidateToken(req.RefreshToken)
	if err != nil {
		apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthExpired, "Invalid or expired refresh token", reqID)
		return
	}

	tokenHash := hashToken(req.RefreshToken)

	// Check if session exists and is not revoked in database
	if h.db != nil {
		var sessionID string
		var revokedAt sql.NullTime
		var expiresAt time.Time

		q := `SELECT id, expires_at, revoked_at FROM user_sessions WHERE refresh_token_hash = $1`
		err := h.db.QueryRowContext(r.Context(), q, tokenHash).Scan(&sessionID, &expiresAt, &revokedAt)
		if err == sql.ErrNoRows {
			// Possible token reuse attack or invalid session
			apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthRevoked, "Session not found or already consumed", reqID)
			return
		} else if err != nil {
			logger.Error("Error querying user session", "error", err)
			apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Internal error", reqID)
			return
		}

		if revokedAt.Valid || time.Now().UTC().After(expiresAt) {
			apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthRevoked, "Session has expired or was revoked", reqID)
			return
		}

		// Rotate token: revoke current session
		now := time.Now().UTC()
		_, _ = h.db.ExecContext(r.Context(), `UPDATE user_sessions SET revoked_at = $1 WHERE id = $2`, now, sessionID)
	}

	// Generate rotated token pair
	newAccess, newRefresh, err := h.tokenService.GenerateTokens(claims.UserID, claims.Email)
	if err != nil {
		apierror.Write(w, http.StatusInternalServerError, apierror.CodeInternalError, "Failed to rotate tokens", reqID)
		return
	}

	// Insert new active session
	if h.db != nil {
		now := time.Now().UTC()
		sessQ := `INSERT INTO user_sessions (id, user_id, refresh_token_hash, user_agent, ip_address, expires_at, created_at, last_used_at)
		          VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`
		_, _ = h.db.ExecContext(r.Context(), sessQ, uuid.New().String(), claims.UserID.String(), hashToken(newRefresh),
			r.UserAgent(), r.RemoteAddr, now.Add(30*24*time.Hour), now, now)
	}

	resp := RefreshResponse{
		AccessToken:  newAccess,
		RefreshToken: newRefresh,
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())

	var req LogoutRequest
	_ = json.NewDecoder(r.Body).Decode(&req)

	if req.RefreshToken != "" && h.db != nil {
		tokenHash := hashToken(req.RefreshToken)
		_, _ = h.db.ExecContext(r.Context(), `UPDATE user_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE refresh_token_hash = $1`, tokenHash)
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"success": true, "message": "Logged out successfully"})
}

func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	reqID := requestid.FromContext(r.Context())
	claims, ok := GetUserClaims(r.Context())
	if !ok {
		apierror.Write(w, http.StatusUnauthorized, apierror.CodeAuthInvalid, "Unauthorized", reqID)
		return
	}

	deviceCount := 0
	policyCount := 0

	if h.db != nil {
		_ = h.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM devices WHERE user_id = $1 AND status != 'REVOKED'`, claims.UserID.String()).Scan(&deviceCount)
		_ = h.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM policies WHERE user_id = $1 AND is_enabled = 1`, claims.UserID.String()).Scan(&policyCount)
	}

	resp := MeResponse{
		User: UserDto{
			ID:    claims.UserID,
			Email: claims.Email,
		},
		ActiveDevicesCount:  deviceCount,
		ActivePoliciesCount: policyCount,
	}

	w.Header().Set("Content-Type", "application/json")
	if reqID != "" {
		w.Header().Set("X-Request-ID", reqID)
	}
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}
