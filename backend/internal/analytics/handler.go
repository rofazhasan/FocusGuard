package analytics

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"time"

	"github.com/focusguard/focusguard/backend/internal/middleware"
	"github.com/focusguard/focusguard/backend/pkg/logger"
)

type Handler struct {
	db *sql.DB
}

func NewHandler(db *sql.DB) *Handler {
	return &Handler{db: db}
}

// GET /api/v1/analytics/daily
func (h *Handler) GetDailyAnalytics(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	todayStr := time.Now().UTC().Format("2006-01-02")
	resp := DailyAnalyticsResponse{
		Date:               todayStr,
		TotalFocusMinutes:  0,
		BudgetUsedMinutes:  0,
		BudgetTotalMinutes: 90,
		RemainingMinutes:   90,
		TopApplications:    []AppUsageDto{},
		BlockedEventsCount: 0,
		ServerTimestamp:    time.Now().UTC().Unix(),
	}

	if h.db != nil {
		// Query cumulative today usage duration
		usageQ := `SELECT target_value, SUM(total_duration_seconds)
		          FROM usage_aggregates
		          WHERE user_id = $1 AND date = $2
		          GROUP BY target_value`
		rows, err := h.db.QueryContext(r.Context(), usageQ, claims.UserID, todayStr)
		if err == nil {
			defer rows.Close()
			totalSec := 0
			for rows.Next() {
				var targetVal string
				var sec int
				if err := rows.Scan(&targetVal, &sec); err == nil {
					totalSec += sec
					resp.TopApplications = append(resp.TopApplications, AppUsageDto{
						Name:         targetVal,
						TargetValue:  targetVal,
						Category:     "Application",
						UsedMinutes:  sec / 60,
						LimitMinutes: 30,
					})
				}
			}
			resp.BudgetUsedMinutes = totalSec / 60
		} else {
			logger.Error("Failed to query daily analytics usage", "error", err)
		}

		// Query blocked events count
		blockedQ := `SELECT COUNT(*) FROM blocked_events WHERE user_id = $1 AND timestamp >= $2`
		todayStart := time.Now().UTC().Truncate(24 * time.Hour)
		var blockedCount int
		if err := h.db.QueryRowContext(r.Context(), blockedQ, claims.UserID, todayStart).Scan(&blockedCount); err == nil {
			resp.BlockedEventsCount = blockedCount
		}

		// Query user policy total limit
		policyQ := `SELECT COALESCE(SUM(limit_seconds), 5400) FROM policies WHERE user_id = $1 AND is_enabled = TRUE`
		var totalLimitSec int
		if err := h.db.QueryRowContext(r.Context(), policyQ, claims.UserID).Scan(&totalLimitSec); err == nil && totalLimitSec > 0 {
			resp.BudgetTotalMinutes = totalLimitSec / 60
		}
	}

	resp.RemainingMinutes = resp.BudgetTotalMinutes - resp.BudgetUsedMinutes
	if resp.RemainingMinutes < 0 {
		resp.RemainingMinutes = 0
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}

// GET /api/v1/analytics/weekly
func (h *Handler) GetWeeklyAnalytics(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	now := time.Now().UTC()
	startOfWeek := now.AddDate(0, 0, -7).Format("2006-01-02")
	endOfWeek := now.Format("2006-01-02")

	resp := WeeklyAnalyticsResponse{
		StartDate:       startOfWeek,
		EndDate:         endOfWeek,
		DailyTrends:     []DailyUsageTrend{},
		TopDistraction:  "None",
		ServerTimestamp: now.Unix(),
	}

	if h.db != nil {
		trendQ := `SELECT date, SUM(total_duration_seconds) / 60
		          FROM usage_aggregates
		          WHERE user_id = $1 AND date >= $2
		          GROUP BY date
		          ORDER BY date ASC`
		rows, err := h.db.QueryContext(r.Context(), trendQ, claims.UserID, startOfWeek)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var dt DailyUsageTrend
				if err := rows.Scan(&dt.Date, &dt.TotalDurationMinutes); err == nil {
					resp.DailyTrends = append(resp.DailyTrends, dt)
				}
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}
