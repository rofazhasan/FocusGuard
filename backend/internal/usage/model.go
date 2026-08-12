package usage

import (
	"time"

	"github.com/google/uuid"
)

type UsageSession struct {
	ID              uuid.UUID `json:"id"`
	DeviceID        uuid.UUID `json:"deviceId"`
	TargetValue     string    `json:"targetValue"`
	StartTime       time.Time `json:"startTime"`
	EndTime         time.Time `json:"endTime"`
	DurationSeconds int       `json:"durationSeconds"`
}

type UsageDelta struct {
	TargetValue     string `json:"targetValue"`
	DurationSeconds int    `json:"durationSeconds"`
	Date            string `json:"date"` // YYYY-MM-DD
}

type UsageSyncRequest struct {
	DeviceID      uuid.UUID    `json:"deviceId"`
	SyncSequence  int64        `json:"syncSequence"`
	UsageDeltas   []UsageDelta `json:"usageDeltas"`
	ClientVersion string       `json:"clientVersion"`
}

type UsageSyncResponse struct {
	ServerTimestamp int64            `json:"serverTimestamp"`
	SyncSequence    int64            `json:"syncSequence"`
	AggregatedTotal map[string]int   `json:"aggregatedTotal"` // targetValue -> totalDurationSeconds
	LimitsReached   []LimitReachedDto `json:"limitsReached,omitempty"`
}

type LimitReachedDto struct {
	PolicyID        uuid.UUID `json:"policyId"`
	TargetValue     string    `json:"targetValue"`
	CurrentUsage    int       `json:"currentUsageSeconds"`
	LimitSeconds    int       `json:"limitSeconds"`
}
