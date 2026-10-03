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

func TestCapabilityPruningLogic(t *testing.T) {
	// A policy containing both a website and an executable target
	policy := Policy{
		Name: "Mixed Distraction Policy",
		Targets: []PolicyTarget{
			{TargetType: TargetWebsite, TargetValue: "youtube.com"},
			{TargetType: TargetApp, TargetValue: "discord.exe"},
		},
	}

	// Extension client simulation: prune TargetApp targets
	clientPlatform := "WEB_EXTENSION"
	prunedTargets := []PolicyTarget{}
	for _, target := range policy.Targets {
		if clientPlatform == "WEB_EXTENSION" && target.TargetType == TargetApp {
			continue // prune native app target
		}
		prunedTargets = append(prunedTargets, target)
	}

	if len(prunedTargets) != 1 {
		t.Fatalf("expected 1 target after pruning, got %d", len(prunedTargets))
	}
	if prunedTargets[0].TargetValue != "youtube.com" {
		t.Errorf("expected target youtube.com retained, got %s", prunedTargets[0].TargetValue)
	}
}

