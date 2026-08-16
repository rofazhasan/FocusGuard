// FocusGuard Windows Agent — Local Policy Engine
// Pure domain logic. No platform dependencies. Fully testable in isolation.
//
// Implements the FocusGuard Policy Evaluation Pipeline:
//   Input → Normalize → Applicable policies → Schedule check →
//   Usage check → Priority resolution → Conflict resolution → Decision

using FocusGuard.Windows.Domain.Models;

namespace FocusGuard.Windows.Domain;

/// <summary>
/// The FocusGuard local policy evaluation engine.
/// Evaluates access requests against locally cached policies without network dependency.
/// Thread-safe for concurrent usage tick and navigation evaluation calls.
/// </summary>
public sealed class LocalPolicyEngine
{
    private readonly object _lock = new();
    private List<Policy> _policies = [];
    private Dictionary<string, int> _todayUsage = new(StringComparer.OrdinalIgnoreCase);
    private int _currentPolicyVersion = 0;
    private bool _isFocusSessionActive;
    private string[] _focusAllowedDomains = [];

    // ── Policy Version Management ────────────────────────────────────────────

    /// <summary>
    /// Returns true if incomingVersion is a valid monotonic upgrade.
    /// Rejects downgrades (v42 → v41 = invalid).
    /// </summary>
    public bool IsValidVersionTransition(int incomingVersion)
    {
        lock (_lock)
        {
            return incomingVersion >= _currentPolicyVersion;
        }
    }

    /// <summary>
    /// Replaces local policy store. Validates version monotonicity before accepting.
    /// </summary>
    /// <returns>True if applied; false if rejected as a rollback attempt.</returns>
    public bool ApplyPolicies(IEnumerable<Policy> policies, int version)
    {
        lock (_lock)
        {
            if (version < _currentPolicyVersion)
            {
                return false; // Reject version rollback
            }
            _policies = policies.Where(p => p.IsEnabled).ToList();
            _currentPolicyVersion = version;
            return true;
        }
    }

    /// <summary>
    /// Records usage delta for a target (domain or app). Thread-safe.
    /// </summary>
    public void RecordUsage(string target, int deltaSeconds)
    {
        var normalized = target.ToLowerInvariant();
        lock (_lock)
        {
            _todayUsage.TryGetValue(normalized, out var current);
            _todayUsage[normalized] = current + deltaSeconds;
        }
    }

    /// <summary>
    /// Replaces the full today usage map (e.g. after loading from local SQLite).
    /// </summary>
    public void SetTodayUsage(Dictionary<string, int> usage)
    {
        lock (_lock)
        {
            _todayUsage = new Dictionary<string, int>(usage, StringComparer.OrdinalIgnoreCase);
        }
    }

    /// <summary>
    /// Sets focus session state. When active, unlisted domains are blocked.
    /// </summary>
    public void SetFocusSession(bool isActive, string[] allowedDomains)
    {
        lock (_lock)
        {
            _isFocusSessionActive = isActive;
            _focusAllowedDomains = allowedDomains;
        }
    }

    /// <summary>
    /// Gets today's accumulated usage for a specific target.
    /// </summary>
    public int GetUsageSeconds(string target)
    {
        lock (_lock)
        {
            _todayUsage.TryGetValue(target.ToLowerInvariant(), out var usage);
            return usage;
        }
    }

    /// <summary>
    /// Returns a snapshot of today's usage dictionary for persistence / sync.
    /// </summary>
    public Dictionary<string, int> GetTodayUsageSnapshot()
    {
        lock (_lock)
        {
            return new Dictionary<string, int>(_todayUsage, StringComparer.OrdinalIgnoreCase);
        }
    }

    public int PolicyVersion
    {
        get { lock (_lock) { return _currentPolicyVersion; } }
    }

    // ── Policy Evaluation Pipeline ───────────────────────────────────────────

    /// <summary>
    /// Evaluates whether access to the target is allowed, warned, or blocked.
    /// Called on every navigation (browser adapter) and foreground app change.
    /// </summary>
    public PolicyDecision Evaluate(string target, PolicyTargetType targetType, DateTimeOffset? now = null)
    {
        var evalTime = now ?? DateTimeOffset.Now;

        List<Policy> policies;
        Dictionary<string, int> usage;
        bool focusActive;
        string[] focusAllowed;

        lock (_lock)
        {
            policies = _policies;
            usage = _todayUsage;
            focusActive = _isFocusSessionActive;
            focusAllowed = _focusAllowedDomains;
        }

        if (policies.Count == 0)
        {
            return new PolicyDecision(DecisionOutcome.Allow, "NO_POLICIES_DEFINED", null, _currentPolicyVersion);
        }

        // 1. Focus session override: block everything not explicitly allowed
        if (focusActive && targetType == PolicyTargetType.Domain)
        {
            var normalizedTarget = DomainNormalizer.GetBaseDomain(target);
            bool isAllowed = focusAllowed.Any(d =>
                DomainNormalizer.Matches(normalizedTarget, d));

            if (!isAllowed)
            {
                return new PolicyDecision(DecisionOutcome.Block, "FOCUS_MODE_ACTIVE", null, _currentPolicyVersion);
            }
        }

        // 2. Find matching policies sorted by priority (highest first)
        var matched = policies
            .Where(p => p.TargetType == targetType && MatchesTarget(target, p.Target, targetType))
            .OrderByDescending(p => p.Priority)
            .ToList();

        if (matched.Count == 0)
        {
            return new PolicyDecision(DecisionOutcome.Allow, "NO_MATCHING_RULES", null, _currentPolicyVersion);
        }

        // 3. Evaluate each policy in priority order
        foreach (var policy in matched)
        {
            if (!IsScheduleActive(policy.Schedule, evalTime))
                continue;

            switch (policy.Action)
            {
                case PolicyAction.Allow:
                    return new PolicyDecision(DecisionOutcome.Allow, "EXPLICIT_ALLOW_RULE", policy.Id, policy.Version);

                case PolicyAction.Block:
                case PolicyAction.NetworkBlock:
                    return new PolicyDecision(DecisionOutcome.Block, "SCHEDULED_BLOCK_ACTIVE", policy.Id, policy.Version);

                case PolicyAction.Focus:
                    return new PolicyDecision(DecisionOutcome.Block, "FOCUS_MODE_ACTIVE", policy.Id, policy.Version);

                case PolicyAction.TimeLimit:
                case PolicyAction.AppLimit:
                {
                    var normalizedKey = target.ToLowerInvariant();
                    usage.TryGetValue(normalizedKey, out var usedSecs);
                    int limit = policy.LimitSeconds;

                    if (usedSecs >= limit)
                    {
                        return new PolicyDecision(DecisionOutcome.Block, "TIME_LIMIT_EXCEEDED",
                            policy.Id, policy.Version, usedSecs, limit);
                    }
                    if (limit > 0 && usedSecs >= (int)(limit * 0.9))
                    {
                        return new PolicyDecision(DecisionOutcome.Warn, "TIME_LIMIT_90_PERCENT",
                            policy.Id, policy.Version, usedSecs, limit);
                    }
                    if (limit > 0 && usedSecs >= (int)(limit * 0.8))
                    {
                        return new PolicyDecision(DecisionOutcome.Warn, "TIME_LIMIT_80_PERCENT",
                            policy.Id, policy.Version, usedSecs, limit);
                    }
                    return new PolicyDecision(DecisionOutcome.Allow, "WITHIN_TIME_LIMIT",
                        policy.Id, policy.Version, usedSecs, limit);
                }
            }
        }

        return new PolicyDecision(DecisionOutcome.Allow, "DEFAULT_ALLOW", null, _currentPolicyVersion);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static bool MatchesTarget(string target, string ruleTarget, PolicyTargetType type)
    {
        return type switch
        {
            PolicyTargetType.Domain => DomainNormalizer.Matches(target, ruleTarget),
            PolicyTargetType.App => string.Equals(target, ruleTarget, StringComparison.OrdinalIgnoreCase),
            PolicyTargetType.Category => string.Equals(target, ruleTarget, StringComparison.OrdinalIgnoreCase),
            _ => false
        };
    }

    private static bool IsScheduleActive(PolicySchedule? schedule, DateTimeOffset now)
    {
        if (schedule is null) return true;

        // Day check (0=Sun...6=Sat)
        if (schedule.Days is { Length: > 0 })
        {
            int dayOfWeek = (int)now.DayOfWeek;
            if (!schedule.Days.Contains(dayOfWeek)) return false;
        }

        // Time window check
        if (schedule.Start is not null && schedule.End is not null)
        {
            var currentMinutes = now.Hour * 60 + now.Minute;
            var (startH, startM) = ParseTime(schedule.Start);
            var (endH, endM) = ParseTime(schedule.End);
            int startMinutes = startH * 60 + startM;
            int endMinutes = endH * 60 + endM;

            if (startMinutes <= endMinutes)
                return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
            else
                return currentMinutes >= startMinutes || currentMinutes <= endMinutes; // Overnight
        }

        return true;
    }

    private static (int hour, int min) ParseTime(string time)
    {
        var parts = time.Split(':');
        return parts.Length == 2
            ? (int.Parse(parts[0]), int.Parse(parts[1]))
            : (0, 0);
    }
}
