package analytics

type AppUsageDto struct {
	Name         string `json:"name"`
	TargetValue  string `json:"targetValue"`
	Category     string `json:"category"`
	UsedMinutes  int    `json:"usedMinutes"`
	UsedSeconds  int    `json:"usedSeconds"`
	LimitMinutes int    `json:"limitMinutes"`
}

type WebsiteUsageDto struct {
	Domain        string `json:"domain"`
	TotalSeconds  int    `json:"totalSeconds"`
	FormattedTime string `json:"formattedTime"`
	UsedMinutes   int    `json:"usedMinutes"`
	Category      string `json:"category"`
	IsDistraction bool   `json:"isDistraction"`
	PolicyName    string `json:"policyName,omitempty"`
	LimitSeconds  int    `json:"limitSeconds,omitempty"`
	IsExceeded    bool   `json:"isExceeded"`
}

type WebsiteAnalyticsResponse struct {
	Date          string            `json:"date"`
	TotalSeconds  int               `json:"totalSeconds"`
	FormattedTime string            `json:"formattedTime"`
	Websites      []WebsiteUsageDto `json:"websites"`
}


type AttentionScoreBreakdown struct {
	OverallScore          int    `json:"overallScore"` // 0 - 100
	FocusCompletionPoints int    `json:"focusCompletionPoints"`
	LimitAdherencePoints  int    `json:"limitAdherencePoints"`
	DistractionDeductions int    `json:"distractionDeductions"`
	BlockedAttemptsShield int    `json:"blockedAttemptsShield"`
	Rating                string `json:"rating"` // "EXCELLENT", "GOOD", "NEEDS_IMPROVEMENT"
	FormulaSummary        string `json:"formulaSummary"`
}

type DailyAnalyticsResponse struct {
	Date                string                  `json:"date"`
	TotalFocusMinutes   int                     `json:"totalFocusMinutes"`
	BudgetUsedMinutes   int                     `json:"budgetUsedMinutes"`
	BudgetTotalMinutes  int                     `json:"budgetTotalMinutes"`
	RemainingMinutes    int                     `json:"remainingMinutes"`
	TopApplications     []AppUsageDto           `json:"topApplications"`
	BlockedEventsCount  int                     `json:"blockedEventsCount"`
	AttentionScore      AttentionScoreBreakdown `json:"attentionScore"`
	ServerTimestamp     int64                   `json:"serverTimestamp"`
}

type TimelineBlock struct {
	Time            string `json:"time"` // e.g. "09:20 AM"
	Label           string `json:"label"`
	Category        string `json:"category"`
	DurationMinutes int    `json:"durationMinutes"`
	BlockType       string `json:"blockType"` // "FOCUS", "PRODUCTIVE", "DISTRACTION", "BLOCKED"
}

type TimelineResponse struct {
	Date            string          `json:"date"`
	Blocks          []TimelineBlock `json:"blocks"`
	ProductiveHours float64         `json:"productiveHours"`
	DistractionMins int             `json:"distractionMins"`
	FocusHours      float64         `json:"focusHours"`
	TopDistraction  string          `json:"topDistraction"`
}

type DailyUsageTrend struct {
	Date                 string `json:"date"`
	TotalDurationMinutes int    `json:"totalDurationMinutes"`
}

type WeeklyAnalyticsResponse struct {
	StartDate       string            `json:"startDate"`
	EndDate         string            `json:"endDate"`
	DailyTrends     []DailyUsageTrend `json:"dailyTrends"`
	TopDistraction  string            `json:"topDistraction"`
	AverageFocus    string            `json:"averageFocus"`
	AttentionScore  int               `json:"attentionScore"`
	ServerTimestamp int64             `json:"serverTimestamp"`
}
