package analytics

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
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

// CalculateAttentionScore implements a transparent formula:
// Focus (max 40) + Limit Adherence (max 30) + Distraction Control (max 20) + Protection Shield (max 10) = 100
func CalculateAttentionScore(focusMins, usedMins, totalBudgetMins, blockedCount int) AttentionScoreBreakdown {
	focusPoints := 0
	if focusMins >= 60 {
		focusPoints = 40
	} else {
		focusPoints = int((float64(focusMins) / 60.0) * 40.0)
	}

	adherencePoints := 30
	if totalBudgetMins > 0 && usedMins > totalBudgetMins {
		overage := usedMins - totalBudgetMins
		adherencePoints = max(0, 30-overage*2)
	}

	distractionDeductions := min(20, (usedMins/15)*5)
	shieldPoints := min(10, blockedCount*2)

	total := max(0, min(100, focusPoints+adherencePoints-distractionDeductions+shieldPoints))

	rating := "NEEDS_IMPROVEMENT"
	if total >= 80 {
		rating = "EXCELLENT"
	} else if total >= 60 {
		rating = "GOOD"
	}

	return AttentionScoreBreakdown{
		OverallScore:          total,
		FocusCompletionPoints: focusPoints,
		LimitAdherencePoints:  adherencePoints,
		DistractionDeductions: distractionDeductions,
		BlockedAttemptsShield: shieldPoints,
		Rating:                rating,
		FormulaSummary:        "Score = Focus(40 max) + Adherence(30 max) - Distraction(20 max) + Protection(10 max)",
	}
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
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
		// 1. Query cumulative today usage duration
		usageQ := `SELECT target_value, SUM(total_duration_seconds)
		          FROM usage_aggregates
		          WHERE user_id = $1 AND date = $2
		          GROUP BY target_value
		          ORDER BY SUM(total_duration_seconds) DESC`
		rows, err := h.db.QueryContext(r.Context(), usageQ, claims.UserID.String(), todayStr)
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
						Category:     "Active Media / App",
						UsedMinutes:  sec / 60,
						LimitMinutes: 30,
					})
				}
			}
			resp.BudgetUsedMinutes = totalSec / 60
		} else {
			logger.Error("Failed to query daily analytics usage", "error", err)
		}

		// 2. Query completed focus minutes today
		focusQ := `SELECT COALESCE(SUM(duration_minutes), 0) FROM focus_sessions
		          WHERE user_id = $1 AND is_completed = 1 AND started_at >= $2`
		todayStart := time.Now().UTC().Truncate(24 * time.Hour)
		var focusMins int
		if err := h.db.QueryRowContext(r.Context(), focusQ, claims.UserID.String(), todayStart).Scan(&focusMins); err == nil {
			resp.TotalFocusMinutes = focusMins
		}

		// 3. Query blocked events count
		blockedQ := `SELECT COUNT(*) FROM blocked_events WHERE user_id = $1 AND timestamp >= $2`
		var blockedCount int
		if err := h.db.QueryRowContext(r.Context(), blockedQ, claims.UserID.String(), todayStart).Scan(&blockedCount); err == nil {
			resp.BlockedEventsCount = blockedCount
		}

		// 4. Query user policy total limit
		policyQ := `SELECT COALESCE(SUM(limit_seconds), 5400) FROM policies WHERE user_id = $1 AND is_enabled = 1`
		var totalLimitSec int
		if err := h.db.QueryRowContext(r.Context(), policyQ, claims.UserID.String()).Scan(&totalLimitSec); err == nil && totalLimitSec > 0 {
			resp.BudgetTotalMinutes = totalLimitSec / 60
		}
	}

	resp.RemainingMinutes = resp.BudgetTotalMinutes - resp.BudgetUsedMinutes
	if resp.RemainingMinutes < 0 {
		resp.RemainingMinutes = 0
	}

	resp.AttentionScore = CalculateAttentionScore(resp.TotalFocusMinutes, resp.BudgetUsedMinutes, resp.BudgetTotalMinutes, resp.BlockedEventsCount)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}

// GET /api/v1/analytics/timeline
func (h *Handler) GetTimeline(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	todayStr := time.Now().UTC().Format("2006-01-02")
	resp := TimelineResponse{
		Date:            todayStr,
		Blocks:          []TimelineBlock{},
		ProductiveHours: 0,
		DistractionMins: 0,
		FocusHours:      0,
		TopDistraction:  "None",
	}

	if h.db != nil {
		// 1. Query real usage aggregates for today
		usageQ := `SELECT target_value, SUM(total_duration_seconds)
		          FROM usage_aggregates
		          WHERE user_id = $1 AND date = $2
		          GROUP BY target_value
		          ORDER BY SUM(total_duration_seconds) DESC`
		rows, err := h.db.QueryContext(r.Context(), usageQ, claims.UserID.String(), todayStr)
		if err == nil {
			defer rows.Close()
			maxDistractSec := 0
			totalUsageSec := 0
			for rows.Next() {
				var targetVal string
				var sec int
				if err := rows.Scan(&targetVal, &sec); err == nil {
					mins := sec / 60
					if mins <= 0 && sec > 0 {
						mins = 1
					}
					totalUsageSec += sec
					blockType := "PRODUCTIVE"
					category := "APPLICATION"

					lowerTarget := strings.ToLower(targetVal)
					if strings.Contains(lowerTarget, "youtube") || strings.Contains(lowerTarget, "reddit") ||
						strings.Contains(lowerTarget, "netflix") || strings.Contains(lowerTarget, "twitter") ||
						strings.Contains(lowerTarget, "x.com") || strings.Contains(lowerTarget, "instagram") ||
						strings.Contains(lowerTarget, "tiktok") || strings.Contains(lowerTarget, "facebook") {
						blockType = "DISTRACTION"
						category = "MEDIA / SOCIAL"
						resp.DistractionMins += mins
						if sec > maxDistractSec {
							maxDistractSec = sec
							resp.TopDistraction = targetVal
						}
					}

					resp.Blocks = append(resp.Blocks, TimelineBlock{
						Time:            "Today",
						Label:           targetVal,
						Category:        category,
						DurationMinutes: mins,
						BlockType:       blockType,
					})
				}
			}
			resp.ProductiveHours = float64(totalUsageSec-resp.DistractionMins*60) / 3600.0
			if resp.ProductiveHours < 0 {
				resp.ProductiveHours = 0
			}
		}

		// 2. Query real focus sessions today
		focusQ := `SELECT duration_minutes, started_at FROM focus_sessions
		          WHERE user_id = $1 AND started_at >= $2`
		todayStart := time.Now().UTC().Truncate(24 * time.Hour)
		frows, err := h.db.QueryContext(r.Context(), focusQ, claims.UserID.String(), todayStart)
		if err == nil {
			defer frows.Close()
			totalFocusMins := 0
			for frows.Next() {
				var fMins int
				var startedAt time.Time
				if err := frows.Scan(&fMins, &startedAt); err == nil {
					totalFocusMins += fMins
					resp.Blocks = append(resp.Blocks, TimelineBlock{
						Time:            startedAt.Format("03:04 PM"),
						Label:           "Remote Focus Lockdown",
						Category:        "FOCUS",
						DurationMinutes: fMins,
						BlockType:       "FOCUS",
					})
				}
			}
			resp.FocusHours = float64(totalFocusMins) / 60.0
		}
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

	today := time.Now().UTC()
	startOfWeek := today.AddDate(0, 0, -6).Format("2006-01-02")
	endOfWeek := today.Format("2006-01-02")

	resp := WeeklyAnalyticsResponse{
		StartDate:       startOfWeek,
		EndDate:         endOfWeek,
		DailyTrends:     []DailyUsageTrend{},
		TopDistraction:  "None",
		AverageFocus:    "0m / day",
		AttentionScore:  100,
		ServerTimestamp: time.Now().UTC().Unix(),
	}

	// Map of dates to duration in minutes
	dateUsage := make(map[string]int)
	if h.db != nil {
		q := `SELECT date, SUM(total_duration_seconds)
		      FROM usage_aggregates
		      WHERE user_id = $1 AND date >= $2 AND date <= $3
		      GROUP BY date`
		rows, err := h.db.QueryContext(r.Context(), q, claims.UserID.String(), startOfWeek, endOfWeek)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var d string
				var sec int
				if err := rows.Scan(&d, &sec); err == nil {
					dateUsage[d] = sec / 60
				}
			}
		}

		// Query top distraction across the week
		topQ := `SELECT target_value FROM usage_aggregates
		        WHERE user_id = $1 AND date >= $2 AND date <= $3
		        GROUP BY target_value
		        ORDER BY SUM(total_duration_seconds) DESC LIMIT 1`
		var topTarget string
		if err := h.db.QueryRowContext(r.Context(), topQ, claims.UserID.String(), startOfWeek, endOfWeek).Scan(&topTarget); err == nil && topTarget != "" {
			resp.TopDistraction = topTarget
		}

		// Query focus minutes
		var totalFocusMins int
		fQ := `SELECT COALESCE(SUM(duration_minutes), 0) FROM focus_sessions
		      WHERE user_id = $1 AND started_at >= $2`
		_ = h.db.QueryRowContext(r.Context(), fQ, claims.UserID.String(), today.AddDate(0, 0, -6)).Scan(&totalFocusMins)
		if totalFocusMins > 0 {
			avgMins := totalFocusMins / 7
			resp.AverageFocus = fmt.Sprintf("%dm / day", avgMins)
		}
	}

	for i := 6; i >= 0; i-- {
		d := today.AddDate(0, 0, -i).Format("2006-01-02")
		resp.DailyTrends = append(resp.DailyTrends, DailyUsageTrend{
			Date:                 d,
			TotalDurationMinutes: dateUsage[d],
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}

type EnforcementTimelineEvent struct {
	Timestamp string `json:"timestamp"`
	Action    string `json:"action"`
	Target    string `json:"target"`
	Device    string `json:"device"`
	Layer     string `json:"layer"`
	Details   string `json:"details"`
}

type SmartRecommendation struct {
	ID              string `json:"id"`
	Title           string `json:"title"`
	Insight         string `json:"insight"`
	SuggestedPolicy string `json:"suggestedPolicy"`
	Target          string `json:"target"`
	LimitMinutes    int    `json:"limitMinutes"`
	Category        string `json:"category"`
}

func (h *Handler) GetEnforcementTimeline(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	events := []EnforcementTimelineEvent{}

	if h.db != nil {
		// Query real audit logs from database
		auditQ := `SELECT action, details, timestamp FROM audit_logs
		          WHERE user_id = $1 ORDER BY timestamp DESC LIMIT 20`
		rows, err := h.db.QueryContext(r.Context(), auditQ, claims.UserID.String())
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var action, details string
				var ts time.Time
				if err := rows.Scan(&action, &details, &ts); err == nil {
					layer := "CLOUD_ENGINE"
					if strings.Contains(action, "DEVICE") || strings.Contains(action, "ENROLL") {
						layer = "FLEET_MGMT"
					} else if strings.Contains(action, "FOCUS") {
						layer = "FOCUS_LOCK"
					} else if strings.Contains(action, "POLICY") {
						layer = "POLICY_SYNC"
					} else if strings.Contains(action, "TAMPER") {
						layer = "SECURITY"
					}

					events = append(events, EnforcementTimelineEvent{
						Timestamp: ts.Format("15:04:05"),
						Action:    action,
						Target:    "Fleet Policies",
						Device:    "Fleet Node",
						Layer:     layer,
						Details:   details,
					})
				}
			}
		}

		// Also query blocked_events
		blockQ := `SELECT target_value, timestamp FROM blocked_events
		          WHERE user_id = $1 ORDER BY timestamp DESC LIMIT 10`
		brows, err := h.db.QueryContext(r.Context(), blockQ, claims.UserID.String())
		if err == nil {
			defer brows.Close()
			for brows.Next() {
				var targetVal string
				var ts time.Time
				if err := brows.Scan(&targetVal, &ts); err == nil {
					events = append(events, EnforcementTimelineEvent{
						Timestamp: ts.Format("15:04:05"),
						Action:    "LIMIT_EXHAUSTED",
						Target:    targetVal,
						Device:    "Local Node",
						Layer:     "BROWSER_DNR / SINKHOLE",
						Details:   fmt.Sprintf("Attention limit exceeded for %s. Shield active.", targetVal),
					})
				}
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(events)
}

func (h *Handler) GetRecommendations(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.GetUserClaims(r.Context())
	if !ok {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	recs := []SmartRecommendation{}

	if h.db != nil {
		// Find real heavy usage targets (> 15 minutes) without existing strict limit
		todayStr := time.Now().UTC().Format("2006-01-02")
		q := `SELECT target_value, SUM(total_duration_seconds)
		      FROM usage_aggregates
		      WHERE user_id = $1 AND date = $2
		      GROUP BY target_value
		      HAVING SUM(total_duration_seconds) >= 900
		      ORDER BY SUM(total_duration_seconds) DESC LIMIT 5`
		rows, err := h.db.QueryContext(r.Context(), q, claims.UserID.String(), todayStr)
		if err == nil {
			defer rows.Close()
			idx := 1
			for rows.Next() {
				var targetVal string
				var sec int
				if err := rows.Scan(&targetVal, &sec); err == nil {
					mins := sec / 60
					category := "MEDIA"
					lower := strings.ToLower(targetVal)
					if strings.Contains(lower, "social") || strings.Contains(lower, "twitter") || strings.Contains(lower, "instagram") || strings.Contains(lower, "reddit") {
						category = "SOCIAL"
					} else if strings.Contains(lower, "youtube") || strings.Contains(lower, "netflix") || strings.Contains(lower, "video") {
						category = "VIDEO"
					}

					recs = append(recs, SmartRecommendation{
						ID:              fmt.Sprintf("rec-real-%d", idx),
						Title:           fmt.Sprintf("Limit %s", targetVal),
						Insight:         fmt.Sprintf("FocusGuard detected %dm active usage for %s today.", mins, targetVal),
						SuggestedPolicy: fmt.Sprintf("Set a 30m daily budget on %s to protect focus.", targetVal),
						Target:          targetVal,
						LimitMinutes:    30,
						Category:        category,
					})
					idx++
				}
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(recs)
}

