package usage

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/focusguard/focusguard/backend/internal/events"
	"github.com/focusguard/focusguard/backend/internal/middleware"
	"github.com/focusguard/focusguard/backend/internal/policies"
	"github.com/focusguard/focusguard/backend/pkg/logger"
)

type Handler struct {
	db        *sql.DB
	evaluator *policies.Evaluator
	wsHub     *events.Hub
}

func NewHandler(db *sql.DB, evaluator *policies.Evaluator, wsHub *events.Hub) *Handler {
	return &Handler{
		db:        db,
		evaluator: evaluator,
		wsHub:     wsHub,
	}
}

func (h *Handler) SyncUsage(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var req UsageSyncRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Invalid request payload"}`, http.StatusBadRequest)
		return
	}

	todayStr := time.Now().UTC().Format("2006-01-02")
	aggregatedTotals := make(map[string]int)
	limitsReached := []LimitReachedDto{}

	if h.db != nil {
		tx, err := h.db.BeginTx(r.Context(), nil)
		if err != nil {
			http.Error(w, `{"error":"Transaction error"}`, http.StatusInternalServerError)
			return
		}
		defer tx.Rollback()

		// Upsert daily usage aggregates from deltas
		for _, delta := range req.UsageDeltas {
			if delta.DurationSeconds <= 0 || delta.TargetValue == "" {
				continue
			}
			dateVal := delta.Date
			if dateVal == "" {
				dateVal = todayStr
			}

			upsertQ := `INSERT INTO usage_aggregates (id, user_id, device_id, target_value, date, total_duration_seconds, updated_at)
			            VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP)
			            ON CONFLICT (user_id, device_id, target_value, date)
			            DO UPDATE SET total_duration_seconds = usage_aggregates.total_duration_seconds + EXCLUDED.total_duration_seconds,
			                           updated_at = CURRENT_TIMESTAMP`
			recordID := uuid.New().String()
			_, err := tx.ExecContext(r.Context(), upsertQ, recordID, claims.UserID.String(), req.DeviceID.String(), delta.TargetValue, dateVal, delta.DurationSeconds)
			if err != nil {
				logger.Error("Failed to upsert usage delta", "error", err)
			}
		}

		if err := tx.Commit(); err != nil {
			logger.Error("Failed to commit usage sync transaction", "error", err)
		}

		// Calculate total cross-device usage for user for today
		queryTotals := `SELECT target_value, SUM(total_duration_seconds) FROM usage_aggregates
		                WHERE user_id = $1 AND date = $2 GROUP BY target_value`
		rows, err := h.db.QueryContext(r.Context(), queryTotals, claims.UserID.String(), todayStr)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var targetVal string
				var totalSec int
				if err := rows.Scan(&targetVal, &totalSec); err == nil {
					aggregatedTotals[targetVal] = totalSec
				}
			}
		}

		// Evaluate policies against current aggregated usage
		policyQ := `SELECT p.id, p.name, p.limit_seconds, p.enforcement_mode, p.is_enabled, pt.target_type, pt.target_value
		            FROM policies p
		            JOIN policy_targets pt ON p.id = pt.policy_id
		            WHERE p.user_id = $1 AND p.is_enabled = 1`
		prows, err := h.db.QueryContext(r.Context(), policyQ, claims.UserID.String())
		if err == nil {
			defer prows.Close()
			for prows.Next() {
				var idStr string
				var p policies.Policy
				var pt policies.PolicyTarget
				var isEnabledInt int
				if err := prows.Scan(&idStr, &p.Name, &p.LimitSeconds, &p.EnforcementMode, &isEnabledInt, &pt.TargetType, &pt.TargetValue); err == nil {
					p.ID, _ = uuid.Parse(idStr)
					p.IsEnabled = (isEnabledInt == 1)
					currentUsage := aggregatedTotals[pt.TargetValue]
					if h.evaluator.IsLimitExceeded(p, currentUsage) {
						dto := LimitReachedDto{
							PolicyID:     p.ID,
							TargetValue:  pt.TargetValue,
							CurrentUsage: currentUsage,
							LimitSeconds: p.LimitSeconds,
						}
						limitsReached = append(limitsReached, dto)

						// Broadcast real-time LIMIT_REACHED event to all connected user devices via WebSocket
						if h.wsHub != nil {
							h.wsHub.BroadcastToUser(claims.UserID, events.EventMessage{
								Event:   "LIMIT_REACHED",
								Payload: dto,
							})
						}
					}
				}
			}
		}
	}

	resp := UsageSyncResponse{
		ServerTimestamp: time.Now().UTC().Unix(),
		SyncSequence:    req.SyncSequence + 1,
		AggregatedTotal: aggregatedTotals,
		LimitsReached:   limitsReached,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}
