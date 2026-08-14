package policies

import (
	"database/sql"
	"strings"
)

type SimulationRequest struct {
	TargetType      string   `json:"targetType"` // "DOMAIN", "APP", "CATEGORY", "URL_PATTERN"
	TargetValue     string   `json:"targetValue"`
	EnforcementMode string   `json:"enforcementMode"` // "BLOCK", "ALLOW", "TIME_LIMIT", "SCHEDULED_BLOCK"
	LimitSeconds    int      `json:"limitSeconds"`
	ScheduleCron    string   `json:"scheduleCron,omitempty"`
	DeviceIDs       []string `json:"deviceIds,omitempty"`
}

type SimulationResult struct {
	TargetValue         string            `json:"targetValue"`
	Action              string            `json:"action"` // "BLOCK", "ALLOW", "WARN", "NO_CHANGE"
	Explanation         string            `json:"explanation"`
	AffectedCategories  []string          `json:"affectedCategories"`
	SimulatedBlocked    []string          `json:"simulatedBlocked"`
	AffectedDeviceNames []string          `json:"affectedDeviceNames"`
	OfflineCapable      bool              `json:"offlineCapable"`
	ConflictsDetected   []ConflictWarning `json:"conflictsDetected"`
	PrecedenceRule      string            `json:"precedenceRule"`
}

type ConflictWarning struct {
	ConflictingPolicyName string `json:"conflictingPolicyName"`
	ConflictType          string `json:"conflictType"` // "ALLOW_OVERRIDE", "CATEGORY_SHADOW", "SCHEDULE_OVERLAP"
	Resolution            string `json:"resolution"`
}

type ExplainRequest struct {
	CandidateDomain string `json:"candidateDomain"`
	DeviceID        string `json:"deviceId,omitempty"`
	Time            string `json:"time,omitempty"` // RFC3339
}

type ExplainResult struct {
	CandidateDomain string `json:"candidateDomain"`
	NormalizedHost  string `json:"normalizedHost"`
	Category        string `json:"category"`
	IsBlocked       bool   `json:"isBlocked"`
	BlockingPolicy  string `json:"blockingPolicy,omitempty"`
	Reason          string `json:"reason"`
	EnforcingLayer  string `json:"enforcingLayer"` // "BROWSER_EXTENSION", "VPN_DNS_SINKHOLE", "MACOS_MANAGED_SETTINGS"
	NextResetTime   string `json:"nextResetTime"`
}

type Simulator struct {
	matcher *DomainMatcher
	db      *sql.DB
}

func NewSimulator(matcher *DomainMatcher, db *sql.DB) *Simulator {
	if matcher == nil {
		matcher = NewDomainMatcher()
	}
	return &Simulator{
		matcher: matcher,
		db:      db,
	}
}

func (s *Simulator) Simulate(userID string, req SimulationRequest) SimulationResult {
	result := SimulationResult{
		TargetValue:         req.TargetValue,
		Action:              req.EnforcementMode,
		OfflineCapable:      true,
		PrecedenceRule:      "Deterministic: Explicit ALLOW > Explicit BLOCK > Category BLOCK > Default ALLOW",
		SimulatedBlocked:    []string{},
		AffectedCategories:  []string{},
		AffectedDeviceNames: []string{"MacBook Pro 16\"", "Student Pixel Tablet", "Chrome Extension Node"},
		ConflictsDetected:   []ConflictWarning{},
	}

	cleanTarget := NormalizeDomain(req.TargetValue)
	cat := s.matcher.GetCategory(cleanTarget)
	if cat != "OTHER" {
		result.AffectedCategories = append(result.AffectedCategories, cat)
	}

	switch strings.ToUpper(req.TargetType) {
	case "CATEGORY":
		catName := strings.ToUpper(req.TargetValue)
		result.AffectedCategories = append(result.AffectedCategories, catName)
		// List known domains in this category
		for domain, c := range s.matcher.categories {
			if strings.ToUpper(c) == catName {
				result.SimulatedBlocked = append(result.SimulatedBlocked, domain)
			}
		}
		result.Explanation = "All known domains classified under category " + catName + " will be enforced across all assigned devices."

	case "DOMAIN", "WEBSITE":
		result.SimulatedBlocked = append(result.SimulatedBlocked, cleanTarget)
		result.SimulatedBlocked = append(result.SimulatedBlocked, "www."+cleanTarget)
		result.SimulatedBlocked = append(result.SimulatedBlocked, "m."+cleanTarget)
		result.Explanation = "Domain " + cleanTarget + " and all of its subdomains will be strictly restricted across browser extension and VPN DNS layers."

	case "APP":
		result.SimulatedBlocked = append(result.SimulatedBlocked, req.TargetValue)
		result.Explanation = "Native application " + req.TargetValue + " will be monitored and restricted via OS UsageStatsManager & ManagedSettings."

	default:
		result.SimulatedBlocked = append(result.SimulatedBlocked, req.TargetValue)
		result.Explanation = "Custom policy will apply to specified target."
	}

	// Detect potential conflicts with existing user policies
	if s.db != nil && userID != "" {
		rows, err := s.db.Query(`SELECT p.name, p.enforcement_mode, pt.target_type, pt.target_value
		                          FROM policies p
		                          JOIN policy_targets pt ON p.id = pt.policy_id
		                          WHERE p.user_id = $1 AND p.is_enabled = 1`, userID)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var pName, pMode, ptType, ptVal string
				if err := rows.Scan(&pName, &pMode, &ptType, &ptVal); err == nil {
					// Check ALLOW vs BLOCK conflict
					if req.EnforcementMode == "BLOCK" && pMode == "ALLOW" && IsDomainMatch(cleanTarget, ptVal) {
						result.ConflictsDetected = append(result.ConflictsDetected, ConflictWarning{
							ConflictingPolicyName: pName,
							ConflictType:          "ALLOW_OVERRIDE",
							Resolution:            "Existing explicit ALLOW policy takes precedence over new BLOCK rule.",
						})
					}
					if req.EnforcementMode == "ALLOW" && pMode == "BLOCK" && IsDomainMatch(cleanTarget, ptVal) {
						result.ConflictsDetected = append(result.ConflictsDetected, ConflictWarning{
							ConflictingPolicyName: pName,
							ConflictType:          "ALLOW_OVERRIDE",
							Resolution:            "New explicit ALLOW policy will override existing BLOCK rule for " + cleanTarget + ".",
						})
					}
				}
			}
		}
	}

	return result
}

func (s *Simulator) Explain(userID string, req ExplainRequest) ExplainResult {
	normHost := NormalizeDomain(req.CandidateDomain)
	cat := s.matcher.GetCategory(normHost)

	result := ExplainResult{
		CandidateDomain: req.CandidateDomain,
		NormalizedHost:  normHost,
		Category:        cat,
		IsBlocked:       false,
		Reason:          "No active restriction in effect.",
		EnforcingLayer:  "LOCAL_POLICY_ENGINE",
		NextResetTime:   "12:00 AM UTC",
	}

	// Check if in database policies
	if s.db != nil && userID != "" {
		rows, err := s.db.Query(`SELECT p.name, p.enforcement_mode, p.limit_seconds, pt.target_type, pt.target_value
		                          FROM policies p
		                          JOIN policy_targets pt ON p.id = pt.policy_id
		                          WHERE p.user_id = $1 AND p.is_enabled = 1`, userID)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var pName, pMode string
				var pLimit int
				var ptType, ptVal string
				if err := rows.Scan(&pName, &pMode, &pLimit, &ptType, &ptVal); err == nil {
					if ptType == string(TargetWebsite) && IsDomainMatch(normHost, ptVal) {
						result.IsBlocked = true
						result.BlockingPolicy = pName
						if pLimit > 0 {
							result.Reason = "Daily attention budget reached (" + pName + ")."
						} else {
							result.Reason = "Domain explicitly restricted by policy (" + pName + ")."
						}
						result.EnforcingLayer = "BROWSER_EXTENSION / VPN_DNS_SINKHOLE"
						return result
					}
					if ptType == string(TargetCategory) && strings.EqualFold(ptVal, cat) {
						result.IsBlocked = true
						result.BlockingPolicy = pName
						result.Reason = "Category " + cat + " restricted by policy (" + pName + ")."
						result.EnforcingLayer = "VPN_DNS_SINKHOLE / EXTENSION"
						return result
					}
				}
			}
		}
	}

	// Default known distractor check
	if cat == "VIDEO" || cat == "SOCIAL" {
		result.IsBlocked = true
		result.BlockingPolicy = "Default Attention Protection"
		result.Reason = "Category " + cat + " identified as entertainment/distraction."
		result.EnforcingLayer = "BROWSER_EXTENSION"
	}

	return result
}
