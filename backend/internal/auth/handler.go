package auth

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/pkg/logger"
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

func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var req RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Invalid request payload"}`, http.StatusBadRequest)
		return
	}

	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if req.Email == "" || len(req.Password) < 6 {
		http.Error(w, `{"error":"Email required and password must be at least 6 characters"}`, http.StatusBadRequest)
		return
	}

	hash, err := HashPassword(req.Password)
	if err != nil {
		logger.Error("Failed to hash password", "error", err)
		http.Error(w, `{"error":"Internal server error"}`, http.StatusInternalServerError)
		return
	}

	userID := uuid.New()
	now := time.Now().UTC()

	if h.db != nil {
		query := `INSERT INTO users (id, email, password_hash, created_at, updated_at) VALUES ($1, $2, $3, $4, $5)`
		_, err = h.db.ExecContext(r.Context(), query, userID.String(), req.Email, hash, now, now)
		if err != nil {
			if strings.Contains(err.Error(), "duplicate key") || strings.Contains(err.Error(), "UNIQUE constraint") || strings.Contains(err.Error(), "unique constraint") {
				http.Error(w, `{"error":"User with this email already exists"}`, http.StatusConflict)
				return
			}
			logger.Error("Failed to insert user into DB", "error", err)
			http.Error(w, `{"error":"Database error"}`, http.StatusInternalServerError)
			return
		}
	}

	access, refresh, err := h.tokenService.GenerateTokens(userID, req.Email)
	if err != nil {
		logger.Error("Failed to generate tokens", "error", err)
		http.Error(w, `{"error":"Internal token generation error"}`, http.StatusInternalServerError)
		return
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
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(resp)
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Invalid request payload"}`, http.StatusBadRequest)
		return
	}

	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if req.Email == "" || req.Password == "" {
		http.Error(w, `{"error":"Email and password are required"}`, http.StatusBadRequest)
		return
	}

	var userIDStr string
	var storedHash string

	if h.db != nil {
		query := `SELECT id, password_hash FROM users WHERE email = $1`
		err := h.db.QueryRowContext(r.Context(), query, req.Email).Scan(&userIDStr, &storedHash)
		if err == sql.ErrNoRows {
			http.Error(w, `{"error":"Invalid credentials"}`, http.StatusUnauthorized)
			return
		} else if err != nil {
			logger.Error("Database query error on login", "error", err)
			http.Error(w, `{"error":"Internal server error"}`, http.StatusInternalServerError)
			return
		}

		if !CheckPasswordHash(req.Password, storedHash) {
			http.Error(w, `{"error":"Invalid credentials"}`, http.StatusUnauthorized)
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
		http.Error(w, `{"error":"Internal token generation error"}`, http.StatusInternalServerError)
		return
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
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}
