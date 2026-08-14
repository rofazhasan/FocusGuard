package policies

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/internal/events"
	"github.com/focusguard/focusguard/backend/internal/middleware"
	"github.com/focusguard/focusguard/backend/pkg/logger"
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
		ID:                uuid.New(),
		UserID:            claims.UserID,
		Name:              req.Name,
		LimitSeconds:      req.LimitSeconds,
		Period:            req.Period,
		ScheduleCron:      req.ScheduleCron,
		Timezone:          req.Timezone,
		EnforcementMode:   req.EnforcementMode,
		IsEnabled:         true,
		Version:           1,
		Targets:           req.Targets,
		AssignedDeviceIDs: req.AssignedDeviceIDs,
		CreatedAt:         time.Now().UTC(),
		UpdatedAt:         time.Now().UTC(),
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
		_, err = tx.ExecContext(r.Context(), q, policy.ID.String(), policy.UserID.String(), policy.Name, policy.LimitSeconds,
			string(policy.Period), policy.ScheduleCron, policy.Timezone, string(policy.EnforcementMode), 1, policy.Version, policy.CreatedAt, policy.UpdatedAt)
		if err != nil {
			logger.Error("Failed to insert policy", "error", err)
			http.Error(w, `{"error":"Database error"}`, http.StatusInternalServerError)
			return
		}

		for i := range policy.Targets {
			policy.Targets[i].ID = uuid.New()
			policy.Targets[i].PolicyID = policy.ID
			tq := `INSERT INTO policy_targets (id, policy_id, target_type, target_value) VALUES ($1, $2, $3, $4)`
			_, err = tx.ExecContext(r.Context(), tq, policy.Targets[i].ID.String(), policy.Targets[i].PolicyID.String(), string(policy.Targets[i].TargetType), policy.Targets[i].TargetValue)
			if err != nil {
				logger.Error("Failed to insert policy target", "error", err)
				http.Error(w, `{"error":"Database target insert error"}`, http.StatusInternalServerError)
				return
			}
		}

		// Insert Scoped Device Assignments
		for _, devID := range policy.AssignedDeviceIDs {
			if devID != "" {
				aq := `INSERT INTO policy_assignments (policy_id, device_id) VALUES ($1, $2)
				      ON CONFLICT DO NOTHING`
				_, _ = tx.ExecContext(r.Context(), aq, policy.ID.String(), devID)
			}
		}

		if err := tx.Commit(); err != nil {
			http.Error(w, `{"error":"Transaction commit failed"}`, http.StatusInternalServerError)
			return
		}

		// Log audit event
		auditQ := `INSERT INTO audit_logs (id, user_id, action, details, timestamp)
		          VALUES ($1, $2, 'POLICY_CREATED', $3, CURRENT_TIMESTAMP)`
		_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), claims.UserID.String(), fmt.Sprintf("Created policy %s (Limit: %dm)", policy.Name, policy.LimitSeconds/60))
	}

	// Broadcast POLICY_UPDATED event over WebSocket
	if h.wsHub != nil {
		h.wsHub.BroadcastToUser(claims.UserID, events.EventMessage{
			Event: "POLICY_UPDATED",
			Payload: map[string]interface{}{
				"policyId":      policy.ID.String(),
				"policyName":    policy.Name,
				"version":       policy.Version,
				"limitSeconds":  policy.LimitSeconds,
				"assignedNodes": policy.AssignedDeviceIDs,
			},
		})
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
		rows, err := h.db.QueryContext(r.Context(), q, claims.UserID.String())
		if err != nil {
			logger.Error("Failed to query policies", "error", err)
			http.Error(w, `{"error":"Database error"}`, http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		for rows.Next() {
			var idStr, uidStr, perStr, enfStr string
			var isEnabledInt int
			var p Policy
			var cron sql.NullString
			if err := rows.Scan(&idStr, &uidStr, &p.Name, &p.LimitSeconds, &perStr, &cron, &p.Timezone, &enfStr, &isEnabledInt, &p.Version, &p.CreatedAt, &p.UpdatedAt); err != nil {
				continue
			}
			p.ID, _ = uuid.Parse(idStr)
			p.UserID, _ = uuid.Parse(uidStr)
			p.Period = Period(perStr)
			p.EnforcementMode = EnforcementMode(enfStr)
			p.IsEnabled = (isEnabledInt == 1)

			if cron.Valid {
				p.ScheduleCron = cron.String
			}

			// Query targets for policy
			tq := `SELECT id, policy_id, target_type, target_value FROM policy_targets WHERE policy_id = $1`
			trows, err := h.db.QueryContext(r.Context(), tq, p.ID.String())
			if err == nil {
				p.Targets = []PolicyTarget{}
				for trows.Next() {
					var tidStr, tpidStr, ttypeStr, tval string
					if err := trows.Scan(&tidStr, &tpidStr, &ttypeStr, &tval); err == nil {
						tid, _ := uuid.Parse(tidStr)
						tpid, _ := uuid.Parse(tpidStr)
						p.Targets = append(p.Targets, PolicyTarget{
							ID:          tid,
							PolicyID:    tpid,
							TargetType:  TargetType(ttypeStr),
							TargetValue: tval,
						})
					}
				}
				trows.Close()
			}

			// Query assigned device IDs
			aq := `SELECT device_id FROM policy_assignments WHERE policy_id = $1`
			arows, err := h.db.QueryContext(r.Context(), aq, p.ID.String())
			if err == nil {
				p.AssignedDeviceIDs = []string{}
				for arows.Next() {
					var devID string
					if err := arows.Scan(&devID); err == nil {
						p.AssignedDeviceIDs = append(p.AssignedDeviceIDs, devID)
					}
				}
				arows.Close()
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

	policyID := chi.URLParam(r, "id")
	if policyID == "" {
		http.Error(w, `{"error":"Policy ID required"}`, http.StatusBadRequest)
		return
	}

	if h.db != nil {
		q := `DELETE FROM policies WHERE id = $1 AND user_id = $2`
		_, err := h.db.ExecContext(r.Context(), q, policyID, claims.UserID.String())
		if err != nil {
			logger.Error("Failed to delete policy", "error", err)
			http.Error(w, `{"error":"Database error"}`, http.StatusInternalServerError)
			return
		}

		// Log audit event
		auditQ := `INSERT INTO audit_logs (id, user_id, action, details, timestamp)
		          VALUES ($1, $2, 'POLICY_DELETED', $3, CURRENT_TIMESTAMP)`
		_, _ = h.db.ExecContext(r.Context(), auditQ, uuid.New().String(), claims.UserID.String(), fmt.Sprintf("Deleted policy %s", policyID))
	}

	if h.wsHub != nil {
		h.wsHub.BroadcastToUser(claims.UserID, events.EventMessage{
			Event: "POLICY_DELETED",
			Payload: map[string]string{
				"policyId": policyID,
			},
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "DELETED", "id": policyID})
}

func (h *Handler) SimulatePolicy(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	userID := ""
	if ok {
		userID = claims.UserID.String()
	}

	var req SimulationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Invalid simulation payload"}`, http.StatusBadRequest)
		return
	}

	sim := NewSimulator(nil, h.db)
	result := sim.Simulate(userID, req)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(result)
}

func (h *Handler) ExplainPolicy(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	userID := ""
	if ok {
		userID = claims.UserID.String()
	}

	var req ExplainRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Invalid explain payload"}`, http.StatusBadRequest)
		return
	}

	sim := NewSimulator(nil, h.db)
	result := sim.Explain(userID, req)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(result)
}

