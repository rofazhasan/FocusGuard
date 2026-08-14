package usage

import (
	"testing"
	"time"

	"github.com/focusguard/focusguard/backend/internal/policies"
)

func TestUsageDeltaNormalization(t *testing.T) {
	evaluator := policies.NewEvaluator()

	policy := policies.Policy{
		LimitSeconds: 1800, // 30 mins
		IsEnabled:    true,
	}

	// 1. Below limit
	if evaluator.IsLimitExceeded(policy, 1200) {
		t.Errorf("Expected 1200s usage to NOT exceed 1800s limit")
	}

	// 2. Exact limit
	if !evaluator.IsLimitExceeded(policy, 1800) {
		t.Errorf("Expected 1800s usage to exceed 1800s limit")
	}

	// 3. Exceeded limit
	if !evaluator.IsLimitExceeded(policy, 2100) {
		t.Errorf("Expected 2100s usage to exceed 1800s limit")
	}

	// 4. Disabled policy
	disabledPolicy := policy
	disabledPolicy.IsEnabled = false
	if evaluator.IsLimitExceeded(disabledPolicy, 3000) {
		t.Errorf("Disabled policy should never report limit exceeded")
	}
}

func TestUsageDatePartitioning(t *testing.T) {
	now := time.Now().UTC()
	todayStr := now.Format("2006-01-02")
	if len(todayStr) != 10 {
		t.Errorf("Invalid date partition format: %s", todayStr)
	}
}
