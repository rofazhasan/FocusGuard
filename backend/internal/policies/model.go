package policies

import (
	"time"

	"github.com/google/uuid"
)

type TargetType string

const (
	TargetApp      TargetType = "APP"
	TargetWebsite  TargetType = "WEBSITE"
	TargetCategory TargetType = "CATEGORY"
)

type EnforcementMode string

const (
	ModeBlock          EnforcementMode = "BLOCK"
	ModeFocusOnly      EnforcementMode = "FOCUS_ONLY"
	ModeScheduledBlock EnforcementMode = "SCHEDULED_BLOCK"
)

type Period string

const (
	PeriodDaily  Period = "DAILY"
	PeriodWeekly Period = "WEEKLY"
)

type PolicyTarget struct {
	ID          uuid.UUID  `json:"id"`
	PolicyID    uuid.UUID  `json:"policyId"`
	TargetType  TargetType `json:"targetType"`
	TargetValue string     `json:"targetValue"`
}

type Policy struct {
	ID              uuid.UUID       `json:"id"`
	UserID          uuid.UUID       `json:"userId"`
	Name            string          `json:"name"`
	LimitSeconds    int             `json:"limitSeconds"`
	Period          Period          `json:"period"`
	ScheduleCron    string          `json:"scheduleCron,omitempty"`
	Timezone        string          `json:"timezone"`
	EnforcementMode EnforcementMode `json:"enforcementMode"`
	IsEnabled       bool            `json:"isEnabled"`
	Version         int             `json:"version"`
	Targets         []PolicyTarget  `json:"targets"`
	CreatedAt       time.Time       `json:"createdAt"`
	UpdatedAt       time.Time       `json:"updatedAt"`
}

type CreatePolicyRequest struct {
	Name            string          `json:"name"`
	LimitSeconds    int             `json:"limitSeconds"`
	Period          Period          `json:"period"`
	ScheduleCron    string          `json:"scheduleCron"`
	Timezone        string          `json:"timezone"`
	EnforcementMode EnforcementMode `json:"enforcementMode"`
	Targets         []PolicyTarget  `json:"targets"`
}
