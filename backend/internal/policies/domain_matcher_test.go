package policies

import (
	"testing"
)

func TestDomainNormalizationAndMatching(t *testing.T) {
	// 1. Exact match
	if !IsDomainMatch("youtube.com", "youtube.com") {
		t.Errorf("Expected exact match for youtube.com")
	}

	// 2. Subdomains
	if !IsDomainMatch("www.youtube.com", "youtube.com") {
		t.Errorf("Expected www.youtube.com to match youtube.com")
	}
	if !IsDomainMatch("m.youtube.com", "youtube.com") {
		t.Errorf("Expected m.youtube.com to match youtube.com")
	}
	if !IsDomainMatch("music.youtube.com", "youtube.com") {
		t.Errorf("Expected music.youtube.com to match youtube.com")
	}

	// 3. Negative Substring Safety: notyoutube.com MUST NOT match youtube.com
	if IsDomainMatch("notyoutube.com", "youtube.com") {
		t.Errorf("CRITICAL SECURITY FLAW: notyoutube.com matched youtube.com!")
	}
	if IsDomainMatch("fake-youtube.com", "youtube.com") {
		t.Errorf("CRITICAL SECURITY FLAW: fake-youtube.com matched youtube.com!")
	}
	if IsDomainMatch("myoutube.com", "youtube.com") {
		t.Errorf("CRITICAL SECURITY FLAW: myoutube.com matched youtube.com!")
	}
}

func TestDomainCategories(t *testing.T) {
	dm := NewDomainMatcher()

	if dm.GetCategory("youtube.com") != "VIDEO" {
		t.Errorf("Expected VIDEO category for youtube.com")
	}
	if dm.GetCategory("www.instagram.com") != "SOCIAL" {
		t.Errorf("Expected SOCIAL category for instagram.com")
	}
	if dm.GetCategory("steampowered.com") != "GAMING" {
		t.Errorf("Expected GAMING category for steampowered.com")
	}
}

func TestPolicyPrecedenceRule(t *testing.T) {
	dm := NewDomainMatcher()

	// Explicit Allowlist beats Emergency Focus Mode
	decision := dm.EvaluateRulePrecedence(
		"canvas.university.edu",
		true, // Emergency focus active
		[]string{"canvas.university.edu"},
		[]Policy{},
		map[string]int{},
	)
	if decision.Action != ActionAllow {
		t.Errorf("Explicit allowlist should override focus mode, got: %s (%s)", decision.Action, decision.Reason)
	}

	// Emergency focus blocks social media
	decision2 := dm.EvaluateRulePrecedence(
		"instagram.com",
		true, // Emergency focus active
		[]string{},
		[]Policy{},
		map[string]int{},
	)
	if decision2.Action != ActionBlock {
		t.Errorf("Active focus mode should block instagram.com, got: %s", decision2.Action)
	}
}
