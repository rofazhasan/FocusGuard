package policies

import (
	"testing"
)

func TestPolicyTargetMatching(t *testing.T) {
	eval := NewEvaluator()

	appTarget := PolicyTarget{TargetType: TargetApp, TargetValue: "com.google.android.youtube"}
	if !eval.IsTargetMatched(appTarget, "com.google.android.youtube") {
		t.Errorf("expected app target match for youtube package")
	}

	if eval.IsTargetMatched(appTarget, "com.instagram.android") {
		t.Errorf("expected app target match failure for different package")
	}

	webTarget := PolicyTarget{TargetType: TargetWebsite, TargetValue: "instagram.com"}
	if !eval.IsTargetMatched(webTarget, "instagram.com") {
		t.Errorf("expected web target match for exact domain")
	}

	if !eval.IsTargetMatched(webTarget, "www.instagram.com") {
		t.Errorf("expected web target match for subdomain")
	}

	if eval.IsTargetMatched(webTarget, "fakeinstagram.com") {
		t.Errorf("expected web target match failure for non-subdomain prefix")
	}
}

func TestLimitExceededCalculation(t *testing.T) {
	eval := NewEvaluator()

	policy := Policy{
		IsEnabled:    true,
		LimitSeconds: 1800, // 30 minutes
	}

	if eval.IsLimitExceeded(policy, 1200) {
		t.Errorf("expected limit NOT exceeded at 1200 seconds")
	}

	if !eval.IsLimitExceeded(policy, 1800) {
		t.Errorf("expected limit EXCEEDED at exactly 1800 seconds")
	}

	if !eval.IsLimitExceeded(policy, 2100) {
		t.Errorf("expected limit EXCEEDED at 2100 seconds")
	}

	policy.IsEnabled = false
	if eval.IsLimitExceeded(policy, 2100) {
		t.Errorf("expected disabled policy to NEVER exceed limit")
	}
}
