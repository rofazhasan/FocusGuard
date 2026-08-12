package policies

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
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

func (h *Handler) CreatePolicy(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var req CreatePolicyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Invalid request payload"}`, http.StatusBadRequest)
		return
	}

	if req.Name == "" || req.LimitSeconds <= 0 {
		http.Error(w, `{"error":"Policy name required and limitSeconds must be positive"}`, http.StatusBadRequest)
		return
	}

	if req.Period == "" {
		req.Period = PeriodDaily
	}
	if req.EnforcementMode == "" {
		req.EnforcementMode = ModeBlock
	}
	if req.Timezone == "" {
		req.Timezone = "UTC"
	}

	policy := Policy{
		ID:              uuid.New(),
		UserID:          claims.UserID,
		Name:            req.Name,
		LimitSeconds:    req.LimitSeconds,
		Period:          req.Period,
		ScheduleCron:    req.ScheduleCron,
		Timezone:        req.Timezone,
		EnforcementMode: req.EnforcementMode,
		IsEnabled:       true,
		Version:         1,
		Targets:         req.Targets,
		CreatedAt:       time.Now().UTC(),
		UpdatedAt:       time.Now().UTC(),
	}

	if h.db != nil {
		tx, err := h.db.BeginTx(r.Context(), nil)
		if err != nil {
			http.Error(w, `{"error":"Transaction error"}`, http.StatusInternalServerError)
			return
		}
		defer tx.Rollback()

		q := `INSERT INTO policies (id, user_id, name, limit_seconds, period, schedule_cron, timezone, enforcement_mode, is_enabled, version, created_at, updated_at)
		      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`
		_, err = tx.ExecContext(r.Context(), q, policy.ID, policy.UserID, policy.Name, policy.LimitSeconds,
			policy.Period, policy.ScheduleCron, policy.Timezone, policy.EnforcementMode, policy.IsEnabled, policy.Version, policy.CreatedAt, policy.UpdatedAt)
		if err != nil {
			logger.Error("Failed to insert policy", "error", err)
			http.Error(w, `{"error":"Database error"}`, http.StatusInternalServerError)
			return
		}

		for i := range policy.Targets {
			policy.Targets[i].ID = uuid.New()
			policy.Targets[i].PolicyID = policy.ID
			tq := `INSERT INTO policy_targets (id, policy_id, target_type, target_value) VALUES ($1, $2, $3, $4)`
			_, err = tx.ExecContext(r.Context(), tq, policy.Targets[i].ID, policy.Targets[i].PolicyID, policy.Targets[i].TargetType, policy.Targets[i].TargetValue)
			if err != nil {
				logger.Error("Failed to insert policy target", "error", err)
				http.Error(w, `{"error":"Database target insert error"}`, http.StatusInternalServerError)
				return
			}
		}

		if err := tx.Commit(); err != nil {
			http.Error(w, `{"error":"Transaction commit failed"}`, http.StatusInternalServerError)
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(policy)
}

func (h *Handler) ListPolicies(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	policiesList := []Policy{}

	if h.db != nil {
		q := `SELECT id, user_id, name, limit_seconds, period, schedule_cron, timezone, enforcement_mode, is_enabled, version, created_at, updated_at
		      FROM policies WHERE user_id = $1 ORDER BY created_at DESC`
		rows, err := h.db.QueryContext(r.Context(), q, claims.UserID)
		if err != nil {
			logger.Error("Failed to query policies", "error", err)
			http.Error(w, `{"error":"Database error"}`, http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		for rows.Next() {
			var p Policy
			var cron sql.NullString
			if err := rows.Scan(&p.ID, &p.UserID, &p.Name, &p.LimitSeconds, &p.Period, &cron, &p.Timezone, &p.EnforcementMode, &p.IsEnabled, &p.Version, &p.CreatedAt, &p.UpdatedAt); err != nil {
				continue
			}
			if cron.Valid {
				p.ScheduleCron = cron.String
			}

			// Query targets for policy
			tq := `SELECT id, policy_id, target_type, target_value FROM policy_targets WHERE policy_id = $1`
			trows, err := h.db.QueryContext(r.Context(), tq, p.ID)
			if err == nil {
				p.Targets = []PolicyTarget{}
				for trows.Next() {
					var pt PolicyTarget
					if err := trows.Scan(&pt.ID, &pt.PolicyID, &pt.TargetType, &pt.TargetValue); err == nil {
						p.Targets = append(p.Targets, pt)
					}
				}
				trows.Close()
			}
			policiesList = append(policiesList, p)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(policiesList)
}

func (h *Handler) DeletePolicy(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	policyIDStr := chi.URLParam(r, "id")
	policyID, err := uuid.Parse(policyIDStr)
	if err != nil {
		http.Error(w, `{"error":"Invalid policy ID"}`, http.StatusBadRequest)
		return
	}

	if h.db != nil {
		q := `DELETE FROM policies WHERE id = $1 AND user_id = $2`
		res, err := h.db.ExecContext(r.Context(), q, policyID, claims.UserID)
		if err != nil {
			http.Error(w, `{"error":"Database error"}`, http.StatusInternalServerError)
			return
		}
		rows, _ := res.RowsAffected()
		if rows == 0 {
			http.Error(w, `{"error":"Policy not found"}`, http.StatusNotFound)
			return
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"deleted"}`))
}
