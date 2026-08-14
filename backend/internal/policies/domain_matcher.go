package policies

import (
	"strings"
)

type DomainMatcher struct {
	categories map[string]string // domain -> category (e.g. "youtube.com" -> "VIDEO")
}

func NewDomainMatcher() *DomainMatcher {
	dm := &DomainMatcher{
		categories: make(map[string]string),
	}
	dm.initDefaultCategories()
	return dm
}

func (dm *DomainMatcher) initDefaultCategories() {
	// Curated Domain Category Database
	// Video & Streaming
	dm.categories["youtube.com"] = "VIDEO"
	dm.categories["netflix.com"] = "VIDEO"
	dm.categories["twitch.tv"] = "VIDEO"
	dm.categories["vimeo.com"] = "VIDEO"
	dm.categories["tiktok.com"] = "VIDEO"

	// Social Networks
	dm.categories["instagram.com"] = "SOCIAL"
	dm.categories["facebook.com"] = "SOCIAL"
	dm.categories["twitter.com"] = "SOCIAL"
	dm.categories["x.com"] = "SOCIAL"
	dm.categories["reddit.com"] = "SOCIAL"
	dm.categories["threads.net"] = "SOCIAL"
	dm.categories["snapchat.com"] = "SOCIAL"

	// Gaming
	dm.categories["steampowered.com"] = "GAMING"
	dm.categories["roblox.com"] = "GAMING"
	dm.categories["epicgames.com"] = "GAMING"
	dm.categories["discord.com"] = "GAMING"
	dm.categories["chess.com"] = "GAMING"

	// Education & Work
	dm.categories["github.com"] = "EDUCATION"
	dm.categories["stackoverflow.com"] = "EDUCATION"
	dm.categories["canvas.instructure.com"] = "EDUCATION"
}

// NormalizeDomain cleans protocols, paths, trailing dots, and standardizes hostnames
func NormalizeDomain(raw string) string {
	raw = strings.TrimSpace(strings.ToLower(raw))
	if raw == "" {
		return ""
	}

	// Strip protocol
	if idx := strings.Index(raw, "://"); idx != -1 {
		raw = raw[idx+3:]
	}

	// Strip path and query parameters
	if idx := strings.IndexAny(raw, "/?#:"); idx != -1 {
		raw = raw[:idx]
	}

	// Strip trailing dots
	raw = strings.TrimRight(raw, ".")

	return raw
}

// IsDomainMatch checks exact or subdomain match safely without false-positive substrings
// Example: "m.youtube.com" matches "youtube.com", but "notyoutube.com" does NOT match "youtube.com"
func IsDomainMatch(candidateDomain, targetDomain string) bool {
	candidate := NormalizeDomain(candidateDomain)
	target := NormalizeDomain(targetDomain)

	if candidate == "" || target == "" {
		return false
	}

	// Strip www. prefix for root comparison
	cleanCandidate := strings.TrimPrefix(candidate, "www.")
	cleanTarget := strings.TrimPrefix(target, "www.")

	// Exact match
	if cleanCandidate == cleanTarget {
		return true
	}

	// Subdomain match (must have dot prefix)
	if strings.HasSuffix(cleanCandidate, "."+cleanTarget) {
		return true
	}

	return false
}

// GetCategory returns domain category or "OTHER"
func (dm *DomainMatcher) GetCategory(domain string) string {
	clean := NormalizeDomain(domain)
	clean = strings.TrimPrefix(clean, "www.")

	// 1. Direct match
	if cat, ok := dm.categories[clean]; ok {
		return cat
	}

	// 2. Parent domain match
	for target, cat := range dm.categories {
		if strings.HasSuffix(clean, "."+target) {
			return cat
		}
	}

	return "OTHER"
}

// Decision Action
type PolicyAction string

const (
	ActionAllow PolicyAction = "ALLOW"
	ActionWarn  PolicyAction = "WARN"
	ActionBlock PolicyAction = "BLOCK"
)

type PolicyDecision struct {
	Action   PolicyAction `json:"action"`
	Reason   string       `json:"reason"`
	PolicyID *string      `json:"policyId,omitempty"`
}

// EvaluateRulePrecedence enforces the strict 6-tier precedence:
// 1. System Safety (Always ALLOW)
// 2. Explicit Allowlist
// 3. Emergency Policy / Remote Focus Lockout
// 4. Explicit Blocklist
// 5. Category Policy
// 6. Default (ALLOW)
func (dm *DomainMatcher) EvaluateRulePrecedence(
	candidateDomain string,
	isEmergencyActive bool,
	allowlist []string,
	explicitPolicies []Policy,
	cumulativeUsageSec map[string]int,
) PolicyDecision {
	clean := NormalizeDomain(candidateDomain)

	// 1. System Safety Allowlist
	if clean == "localhost" || clean == "127.0.0.1" || strings.HasSuffix(clean, ".local") {
		return PolicyDecision{Action: ActionAllow, Reason: "System Safety Loopback"}
	}

	// 2. Explicit Allowlist
	for _, allowed := range allowlist {
		if IsDomainMatch(clean, allowed) {
			return PolicyDecision{Action: ActionAllow, Reason: "Explicitly Allowed Target"}
		}
	}

	// 3. Emergency Lockout / Focus Mode
	if isEmergencyActive {
		cat := dm.GetCategory(clean)
		if cat == "SOCIAL" || cat == "VIDEO" || cat == "GAMING" {
			return PolicyDecision{Action: ActionBlock, Reason: "Active Remote Focus Shield"}
		}
	}

	// 4. Explicit Domain Policy Limits
	for _, p := range explicitPolicies {
		if !p.IsEnabled {
			continue
		}
		for _, target := range p.Targets {
			if target.TargetType == TargetWebsite && IsDomainMatch(clean, target.TargetValue) {
				usedSec := cumulativeUsageSec[target.TargetValue]
				if usedSec >= p.LimitSeconds {
					pID := p.ID.String()
					return PolicyDecision{
						Action:   ActionBlock,
						Reason:   "Daily Attention Budget Reached",
						PolicyID: &pID,
					}
				}
			}
		}
	}

	// 5. Category Policy Limits
	cat := dm.GetCategory(clean)
	for _, p := range explicitPolicies {
		if !p.IsEnabled {
			continue
		}
		for _, target := range p.Targets {
			if target.TargetType == TargetCategory && strings.EqualFold(string(target.TargetValue), cat) {
				usedSec := cumulativeUsageSec[cat]
				if usedSec >= p.LimitSeconds {
					pID := p.ID.String()
					return PolicyDecision{
						Action:   ActionBlock,
						Reason:   "Category Attention Budget Reached (" + cat + ")",
						PolicyID: &pID,
					}
				}
			}
		}
	}

	// 6. Default
	return PolicyDecision{Action: ActionAllow, Reason: "Default Normal State"}
}
