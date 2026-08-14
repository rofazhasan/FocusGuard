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
	todayStr := time.Now().UTC().Format("2006-01-02")
	resp := TimelineResponse{
		Date: todayStr,
		Blocks: []TimelineBlock{
			{Time: "08:00 AM", Label: "Deep Work / Code Review", Category: "WORK", DurationMinutes: 80, BlockType: "PRODUCTIVE"},
			{Time: "09:20 AM", Label: "YouTube (Browsing)", Category: "VIDEO", DurationMinutes: 15, BlockType: "DISTRACTION"},
			{Time: "09:35 AM", Label: "Architecture Design", Category: "WORK", DurationMinutes: 85, BlockType: "PRODUCTIVE"},
			{Time: "11:00 AM", Label: "Remote Focus Session", Category: "FOCUS", DurationMinutes: 60, BlockType: "FOCUS"},
			{Time: "12:00 PM", Label: "Rest / Lunch Break", Category: "BREAK", DurationMinutes: 45, BlockType: "PRODUCTIVE"},
		},
		ProductiveHours: 4.5,
		DistractionMins: 15,
		FocusHours:      2.0,
		TopDistraction:  "YouTube",
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(resp)
}

// GET /api/v1/analytics/weekly
func (h *Handler) GetWeeklyAnalytics(w http.ResponseWriter, r *http.Request) {
	today := time.Now().UTC()
	startOfWeek := today.AddDate(0, 0, -6).Format("2006-01-02")
	endOfWeek := today.Format("2006-01-02")

	resp := WeeklyAnalyticsResponse{
		StartDate:       startOfWeek,
		EndDate:         endOfWeek,
		DailyTrends:     []DailyUsageTrend{},
		TopDistraction:  "YouTube (Video)",
		AverageFocus:    "1h 45m / day",
		AttentionScore:  82,
		ServerTimestamp: time.Now().UTC().Unix(),
	}

	for i := 6; i >= 0; i-- {
		d := today.AddDate(0, 0, -i).Format("2006-01-02")
		resp.DailyTrends = append(resp.DailyTrends, DailyUsageTrend{
			Date:                 d,
			TotalDurationMinutes: 15 + (i*7)%25,
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
	events := []EnforcementTimelineEvent{
		{
			Timestamp: "10:02:11",
			Action:    "POLICY_SYNC",
			Target:    "Fleet Policies (v2)",
			Device:    "All Nodes",
			Layer:     "CLOUD_SYNC",
			Details:   "Synchronized policy v2 with monotonic version counter.",
		},
		{
			Timestamp: "10:02:12",
			Action:    "DNR_COMPILED",
			Target:    "youtube.com",
			Device:    "Chrome Extension Node",
			Layer:     "BROWSER_DNR",
			Details:   "Dynamic declarative rules compiled into browser request engine.",
		},
		{
			Timestamp: "10:02:12",
			Action:    "VPN_RULES_UPDATED",
			Target:    "youtube.com, instagram.com",
			Device:    "Student Pixel Tablet",
			Layer:     "VPN_DNS_SINKHOLE",
			Details:   "Trie DomainPolicyCache updated for packet sinkhole.",
		},
		{
			Timestamp: "10:31:42",
			Action:    "USAGE_WARNING_90",
			Target:    "youtube.com (27m / 30m)",
			Device:    "MacBook Pro 16\"",
			Layer:     "SESSION_TRACKER",
			Details:   "90% budget threshold reached. Displaying progressive notification.",
		},
		{
			Timestamp: "10:31:44",
			Action:    "LIMIT_EXHAUSTED",
			Target:    "youtube.com (30m / 30m)",
			Device:    "Shared Cloud Budget",
			Layer:     "POLICY_ENGINE",
			Details:   "Combined usage across Mac, Tablet, and Extension hit 30m cap.",
		},
		{
			Timestamp: "10:31:44",
			Action:    "DOMAIN_BLOCK_ACTIVATED",
			Target:    "youtube.com",
			Device:    "All Fleet Devices",
			Layer:     "BROWSER_DNR / VPN_SINKHOLE",
			Details:   "DNR redirect and RFC 1035 NXDOMAIN active simultaneously.",
		},
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(events)
}

func (h *Handler) GetRecommendations(w http.ResponseWriter, r *http.Request) {
	recs := []SmartRecommendation{
		{
			ID:              "rec-1",
			Title:           "Night Entertainment Limit",
			Insight:         "FocusGuard detected 1h 48m YouTube usage between 11:00 PM and 01:00 AM.",
			SuggestedPolicy: "Limit YouTube to 30 min daily during late night hours.",
			Target:          "youtube.com",
			LimitMinutes:    30,
			Category:        "VIDEO",
		},
		{
			ID:              "rec-2",
			Title:           "Social Media Study Lock",
			Insight:         "Social apps consumed 38m during scheduled study hours (08:00 AM – 01:00 PM).",
			SuggestedPolicy: "Block Category SOCIAL during weekday morning study blocks.",
			Target:          "SOCIAL",
			LimitMinutes:    0,
			Category:        "SOCIAL",
		},
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(recs)
}

