package policies

import (
	"testing"
)

func TestPolicySimulatorDomainAndCategory(t *testing.T) {
	matcher := NewDomainMatcher()
	sim := NewSimulator(matcher, nil)

	// 1. Simulate Category Block (SOCIAL)
	req := SimulationRequest{
		TargetType:      "CATEGORY",
		TargetValue:     "SOCIAL",
		EnforcementMode: "BLOCK",
	}
	res := sim.Simulate("", req)
	if res.Action != "BLOCK" {
		t.Fatalf("Expected action BLOCK, got %s", res.Action)
	}
	if len(res.SimulatedBlocked) == 0 {
		t.Fatalf("Expected simulated blocked domains for SOCIAL category")
	}

	// 2. Simulate Domain Block (youtube.com)
	reqDomain := SimulationRequest{
		TargetType:      "DOMAIN",
		TargetValue:     "youtube.com",
		EnforcementMode: "BLOCK",
		LimitSeconds:    1800,
	}
	resDomain := sim.Simulate("", reqDomain)
	if len(resDomain.AffectedCategories) == 0 || resDomain.AffectedCategories[0] != "VIDEO" {
		t.Fatalf("Expected category VIDEO for youtube.com, got %v", resDomain.AffectedCategories)
	}
}

func TestPolicyExplainer(t *testing.T) {
	matcher := NewDomainMatcher()
	sim := NewSimulator(matcher, nil)

	req := ExplainRequest{
		CandidateDomain: "https://m.youtube.com/watch?v=xyz",
	}
	res := sim.Explain("", req)
	if !res.IsBlocked {
		t.Fatalf("Expected m.youtube.com to be identified as blocked")
	}
	if res.Category != "VIDEO" {
		t.Fatalf("Expected category VIDEO, got %s", res.Category)
	}
}
