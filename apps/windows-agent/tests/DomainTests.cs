// FocusGuard Windows Agent — Domain Unit Tests
// Pure C# tests. No Win32, WPF, or Windows-specific APIs.
// Can be executed on any .NET 8 platform (Windows, macOS, Linux).
//
// Coverage:
//   1. DomainNormalizer — Normalization, base domain extraction, matching (25 cases)
//   2. LocalPolicyEngine — Policy application, evaluation pipeline, version monotonicity
//   3. Schedule evaluation — Day filtering, time windows, midnight crossing

using FocusGuard.Windows.Domain;
using FocusGuard.Windows.Domain.Models;
using Xunit;
using FluentAssertions;

namespace FocusGuard.Windows.Tests;

// ── 1. DomainNormalizer Tests ──────────────────────────────────────────────────

public sealed class DomainNormalizerTests
{
    // ── NormalizeHostname ──────────────────────────────────────────────────────

    [Theory]
    [InlineData("https://www.youtube.com/watch?v=abc", "www.youtube.com")]
    [InlineData("http://m.youtube.com/", "m.youtube.com")]
    [InlineData("www.youtube.com", "www.youtube.com")]
    [InlineData("YOUTUBE.COM", "youtube.com")]
    [InlineData("example.com:443", "example.com")]
    [InlineData("example.com.", "example.com")]    // Trailing root dot
    [InlineData("", "")]
    [InlineData("   ", "")]
    public void NormalizeHostname_ProducesCorrectResult(string input, string expected)
    {
        DomainNormalizer.NormalizeHostname(input).Should().Be(expected);
    }

    // ── GetBaseDomain ──────────────────────────────────────────────────────────

    [Theory]
    [InlineData("music.youtube.com", "youtube.com")]
    [InlineData("www.youtube.com", "youtube.com")]
    [InlineData("youtube.com", "youtube.com")]
    [InlineData("news.bbc.co.uk", "bbc.co.uk")]      // Multi-TLD: co.uk
    [InlineData("deeply.nested.bbc.co.uk", "bbc.co.uk")]
    [InlineData("user.github.io", "github.io")]       // Known hosting multi-TLD
    [InlineData("example.com", "example.com")]
    public void GetBaseDomain_ExtractsCorrectBaseDomain(string hostname, string expected)
    {
        DomainNormalizer.GetBaseDomain(hostname).Should().Be(expected);
    }

    // ── Matches — Positive Cases ───────────────────────────────────────────────

    [Theory]
    [InlineData("youtube.com", "youtube.com")]               // Exact
    [InlineData("www.youtube.com", "youtube.com")]           // Subdomain
    [InlineData("m.youtube.com", "youtube.com")]             // Subdomain
    [InlineData("music.youtube.com", "youtube.com")]         // Deep subdomain
    [InlineData("a.b.c.youtube.com", "youtube.com")]         // Very deep subdomain
    [InlineData("youtube.com", "*.youtube.com")]             // Wildcard syntax
    [InlineData("www.bbc.co.uk", "bbc.co.uk")]              // Multi-TLD subdomain
    public void Matches_ShouldReturnTrue_ForValidMatches(string target, string rule)
    {
        DomainNormalizer.Matches(target, rule).Should().BeTrue(
            because: $"'{target}' should match rule '{rule}'");
    }

    // ── Matches — Critical Security Rejections ────────────────────────────────

    [Theory]
    [InlineData("notyoutube.com", "youtube.com")]            // Suffix spoofing
    [InlineData("youtube.com.evil.com", "youtube.com")]      // Prefix injection
    [InlineData("fakeyoutube.com", "youtube.com")]           // Substring false match
    [InlineData("xnyoutube.com", "youtube.com")]             // Unrelated domain
    [InlineData("youtube.org", "youtube.com")]               // Different TLD
    [InlineData("", "youtube.com")]                          // Empty target
    [InlineData("youtube.com", "")]                          // Empty rule
    public void Matches_ShouldReturnFalse_ForSecurityRejections(string target, string rule)
    {
        DomainNormalizer.Matches(target, rule).Should().BeFalse(
            because: $"'{target}' must NOT match rule '{rule}' (security invariant)");
    }
}

// ── 2. LocalPolicyEngine Tests ─────────────────────────────────────────────────

public sealed class LocalPolicyEngineTests
{
    private static Policy MakeBlockPolicy(string target, int priority = 10) => new(
        Id: "pol_test_block",
        Version: 1,
        Name: "Test Block",
        TargetType: PolicyTargetType.Domain,
        Target: target,
        Action: PolicyAction.Block,
        LimitSeconds: 0,
        Schedule: null,
        Timezone: "UTC",
        Devices: [],
        Priority: priority,
        IsEnabled: true
    );

    private static Policy MakeTimeLimitPolicy(string target, int limitSeconds, int priority = 10) => new(
        Id: "pol_test_limit",
        Version: 1,
        Name: "Test Time Limit",
        TargetType: PolicyTargetType.Domain,
        Target: target,
        Action: PolicyAction.TimeLimit,
        LimitSeconds: limitSeconds,
        Schedule: null,
        Timezone: "UTC",
        Devices: [],
        Priority: priority,
        IsEnabled: true
    );

    private static Policy MakeAllowPolicy(string target, int priority = 100) => new(
        Id: "pol_test_allow",
        Version: 1,
        Name: "Explicit Allow",
        TargetType: PolicyTargetType.Domain,
        Target: target,
        Action: PolicyAction.Allow,
        LimitSeconds: 0,
        Schedule: null,
        Timezone: "UTC",
        Devices: [],
        Priority: priority,
        IsEnabled: true
    );

    [Fact]
    public void EmptyPolicies_ReturnsAllow()
    {
        var engine = new LocalPolicyEngine();
        var decision = engine.Evaluate("youtube.com", PolicyTargetType.Domain);
        decision.Decision.Should().Be(DecisionOutcome.Allow);
        decision.Reason.Should().Be("NO_POLICIES_DEFINED");
    }

    [Fact]
    public void BlockPolicy_ReturnsBlock()
    {
        var engine = new LocalPolicyEngine();
        engine.ApplyPolicies([MakeBlockPolicy("youtube.com")], 1);

        var decision = engine.Evaluate("www.youtube.com", PolicyTargetType.Domain);
        decision.Decision.Should().Be(DecisionOutcome.Block);
        decision.Reason.Should().Be("SCHEDULED_BLOCK_ACTIVE");
    }

    [Fact]
    public void BlockPolicy_DoesNotMatchUnrelatedDomain()
    {
        var engine = new LocalPolicyEngine();
        engine.ApplyPolicies([MakeBlockPolicy("youtube.com")], 1);

        var decision = engine.Evaluate("notyoutube.com", PolicyTargetType.Domain);
        decision.Decision.Should().Be(DecisionOutcome.Allow);
    }

    [Fact]
    public void TimeLimit_AllowsWithinBudget()
    {
        var engine = new LocalPolicyEngine();
        engine.ApplyPolicies([MakeTimeLimitPolicy("youtube.com", limitSeconds: 3600)], 1);
        engine.RecordUsage("youtube.com", 100);

        var decision = engine.Evaluate("youtube.com", PolicyTargetType.Domain);
        decision.Decision.Should().Be(DecisionOutcome.Allow);
        decision.Reason.Should().Be("WITHIN_TIME_LIMIT");
    }

    [Fact]
    public void TimeLimit_BlocksWhenExceeded()
    {
        var engine = new LocalPolicyEngine();
        engine.ApplyPolicies([MakeTimeLimitPolicy("youtube.com", limitSeconds: 100)], 1);
        engine.RecordUsage("youtube.com", 100);

        var decision = engine.Evaluate("youtube.com", PolicyTargetType.Domain);
        decision.Decision.Should().Be(DecisionOutcome.Block);
        decision.Reason.Should().Be("TIME_LIMIT_EXCEEDED");
        decision.UsedSeconds.Should().Be(100);
        decision.LimitSeconds.Should().Be(100);
    }

    [Fact]
    public void TimeLimit_WarnsAt90Percent()
    {
        var engine = new LocalPolicyEngine();
        engine.ApplyPolicies([MakeTimeLimitPolicy("youtube.com", limitSeconds: 100)], 1);
        engine.RecordUsage("youtube.com", 92); // 92/100 = 92% > 90%

        var decision = engine.Evaluate("youtube.com", PolicyTargetType.Domain);
        decision.Decision.Should().Be(DecisionOutcome.Warn);
        decision.Reason.Should().Be("TIME_LIMIT_90_PERCENT");
    }

    [Fact]
    public void AllowOverrideWithHigherPriority_WinsOverBlock()
    {
        var engine = new LocalPolicyEngine();
        engine.ApplyPolicies([
            MakeBlockPolicy("youtube.com", priority: 10),
            MakeAllowPolicy("kids.youtube.com", priority: 100)
        ], 1);

        // High-priority allow rule should win for kids.youtube.com
        var allowDecision = engine.Evaluate("kids.youtube.com", PolicyTargetType.Domain);
        allowDecision.Decision.Should().Be(DecisionOutcome.Allow);
        allowDecision.Reason.Should().Be("EXPLICIT_ALLOW_RULE");

        // Block should still apply to regular youtube.com
        var blockDecision = engine.Evaluate("www.youtube.com", PolicyTargetType.Domain);
        blockDecision.Decision.Should().Be(DecisionOutcome.Block);
    }

    [Fact]
    public void PolicyVersion_MonotonicIncrement_Accepted()
    {
        var engine = new LocalPolicyEngine();
        engine.ApplyPolicies([], 5);

        engine.IsValidVersionTransition(6).Should().BeTrue();
        engine.IsValidVersionTransition(5).Should().BeTrue(); // Same version OK (idempotent re-apply)
    }

    [Fact]
    public void PolicyVersion_Rollback_Rejected()
    {
        var engine = new LocalPolicyEngine();
        engine.ApplyPolicies([], 10);

        engine.IsValidVersionTransition(9).Should().BeFalse();

        // ApplyPolicies also rejects rollback
        var accepted = engine.ApplyPolicies([], 9);
        accepted.Should().BeFalse();
        engine.PolicyVersion.Should().Be(10); // Unchanged
    }

    [Fact]
    public void FocusSession_BlocksUnlistedDomains()
    {
        var engine = new LocalPolicyEngine();
        engine.ApplyPolicies([], 1);
        engine.SetFocusSession(true, ["github.com", "stackoverflow.com"]);

        var githubDecision = engine.Evaluate("github.com", PolicyTargetType.Domain);
        githubDecision.Decision.Should().Be(DecisionOutcome.Allow);

        var youtubeDecision = engine.Evaluate("youtube.com", PolicyTargetType.Domain);
        youtubeDecision.Decision.Should().Be(DecisionOutcome.Block);
        youtubeDecision.Reason.Should().Be("FOCUS_MODE_ACTIVE");
    }

    [Fact]
    public void FocusSession_Off_ResumesNormalEvaluation()
    {
        var engine = new LocalPolicyEngine();
        engine.ApplyPolicies([], 1);
        engine.SetFocusSession(true, ["github.com"]);
        engine.SetFocusSession(false, []);

        var decision = engine.Evaluate("youtube.com", PolicyTargetType.Domain);
        decision.Decision.Should().Be(DecisionOutcome.Allow);
    }
}

// ── 3. Schedule Evaluation Tests ───────────────────────────────────────────────

public sealed class ScheduleEvaluationTests
{
    private static Policy MakeScheduledBlockPolicy(string[] days, string start, string end) => new(
        Id: "pol_sched",
        Version: 1,
        Name: "Scheduled Block",
        TargetType: PolicyTargetType.Domain,
        Target: "youtube.com",
        Action: PolicyAction.Block,
        LimitSeconds: 0,
        Schedule: new PolicySchedule(
            Days: days.Select(int.Parse).ToArray(),
            Start: start,
            End: end),
        Timezone: "UTC",
        Devices: [],
        Priority: 10,
        IsEnabled: true
    );

    [Fact]
    public void Schedule_WithinWindow_IsActive()
    {
        var engine = new LocalPolicyEngine();
        // Mon–Fri, 09:00–17:00
        engine.ApplyPolicies([MakeScheduledBlockPolicy(["1", "2", "3", "4", "5"], "09:00", "17:00")], 1);

        // Monday at 12:00
        var monday12pm = new DateTimeOffset(2026, 8, 17, 12, 0, 0, TimeSpan.Zero); // Monday
        var decision = engine.Evaluate("youtube.com", PolicyTargetType.Domain, monday12pm);
        decision.Decision.Should().Be(DecisionOutcome.Block);
    }

    [Fact]
    public void Schedule_OutsideWindow_IsInactive()
    {
        var engine = new LocalPolicyEngine();
        engine.ApplyPolicies([MakeScheduledBlockPolicy(["1", "2", "3", "4", "5"], "09:00", "17:00")], 1);

        // Monday at 08:00 (before start)
        var monday8am = new DateTimeOffset(2026, 8, 17, 8, 0, 0, TimeSpan.Zero);
        var decision = engine.Evaluate("youtube.com", PolicyTargetType.Domain, monday8am);
        decision.Decision.Should().Be(DecisionOutcome.Allow);
    }

    [Fact]
    public void Schedule_Weekend_IsInactive_ForWeekdayOnlyRule()
    {
        var engine = new LocalPolicyEngine();
        // Mon–Fri only (1–5)
        engine.ApplyPolicies([MakeScheduledBlockPolicy(["1", "2", "3", "4", "5"], "09:00", "22:00")], 1);

        // Saturday at 14:00
        var saturday2pm = new DateTimeOffset(2026, 8, 15, 14, 0, 0, TimeSpan.Zero); // 2026-08-15 is Saturday
        var decision = engine.Evaluate("youtube.com", PolicyTargetType.Domain, saturday2pm);
        decision.Decision.Should().Be(DecisionOutcome.Allow);
    }

    [Fact]
    public void Schedule_OvernightWindow_WorksAcrossMidnight()
    {
        var engine = new LocalPolicyEngine();
        // Overnight: 22:00–07:00 (night lockdown) on all days
        engine.ApplyPolicies([MakeScheduledBlockPolicy([], "22:00", "07:00")], 1);

        // 23:00 should be blocked
        var elevenPm = new DateTimeOffset(2026, 8, 15, 23, 0, 0, TimeSpan.Zero);
        var blockDecision = engine.Evaluate("youtube.com", PolicyTargetType.Domain, elevenPm);
        blockDecision.Decision.Should().Be(DecisionOutcome.Block);

        // 06:00 should also be blocked (before 07:00 cutoff)
        var sixAm = new DateTimeOffset(2026, 8, 16, 6, 0, 0, TimeSpan.Zero);
        var blockDecision2 = engine.Evaluate("youtube.com", PolicyTargetType.Domain, sixAm);
        blockDecision2.Decision.Should().Be(DecisionOutcome.Block);

        // 12:00 should be allowed
        var noon = new DateTimeOffset(2026, 8, 15, 12, 0, 0, TimeSpan.Zero);
        var allowDecision = engine.Evaluate("youtube.com", PolicyTargetType.Domain, noon);
        allowDecision.Decision.Should().Be(DecisionOutcome.Allow);
    }
}
