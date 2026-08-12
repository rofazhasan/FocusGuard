package analytics

import "time"

type AppUsageDto struct {
	Name         string `json:"name"`
	TargetValue  string `json:"targetValue"`
	Category     string `json:"category"`
	UsedMinutes  int    `json:"usedMinutes"`
	LimitMinutes int    `json:"limitMinutes"`
}

type DailyAnalyticsResponse struct {
	Date                string        `json:"date"`
	TotalFocusMinutes   int           `json:"totalFocusMinutes"`
	BudgetUsedMinutes   int           `json:"budgetUsedMinutes"`
	BudgetTotalMinutes  int           `json:"budgetTotalMinutes"`
	RemainingMinutes    int           `json:"remainingMinutes"`
	TopApplications     []AppUsageDto `json:"topApplications"`
	BlockedEventsCount  int           `json:"blockedEventsCount"`
	ServerTimestamp     int64         `json:"serverTimestamp"`
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
	ServerTimestamp int64             `json:"serverTimestamp"`
}

type HealthTimestampResponse struct {
	Status    string    `json:"status"`
	Timestamp time.Time `json:"timestamp"`
	Version   string    `json:"version"`
}
