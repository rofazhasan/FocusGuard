package policies

import (
	"strings"
)

type Evaluator struct{}

func NewEvaluator() *Evaluator {
	return &Evaluator{}
}

// IsTargetMatched checks if a given app bundle ID or domain matches a policy target
func (e *Evaluator) IsTargetMatched(target PolicyTarget, candidate string) bool {
	candidate = strings.TrimSpace(strings.ToLower(candidate))
	targetVal := strings.TrimSpace(strings.ToLower(target.TargetValue))

	if candidate == "" || targetVal == "" {
		return false
	}

	switch target.TargetType {
	case TargetApp:
		return candidate == targetVal
	case TargetWebsite:
		// Supports domain matching and subdomain wildcard matching (e.g. instagram.com matches www.instagram.com)
		if candidate == targetVal {
			return true
		}
		if strings.HasSuffix(candidate, "."+targetVal) {
			return true
		}
		return false
	case TargetCategory:
		return candidate == targetVal
	default:
		return false
	}
}

// IsLimitExceeded returns true if cumulative usage in seconds meets or exceeds the policy limit
func (e *Evaluator) IsLimitExceeded(policy Policy, cumulativeUsageSeconds int) bool {
	if !policy.IsEnabled {
		return false
	}
	if policy.LimitSeconds <= 0 {
		return false
	}
	return cumulativeUsageSeconds >= policy.LimitSeconds
}
