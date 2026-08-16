// FocusGuard Windows Agent — Domain Layer
// PSL-aware hostname normalizer and subdomain matcher.
// Port of packages/domain-engine into C# — same precision guarantees.
// NEVER uses string.Contains() for domain matching.

namespace FocusGuard.Windows.Domain;

/// <summary>
/// Enterprise-grade hostname normalization and domain matching engine.
/// Implements the FocusGuard domain matching specification:
///   - Exact match
///   - Full subdomain match (strictly preceded by '.')
///   - Never substring match
///   - PSL multi-level TLD awareness
/// </summary>
public static class DomainNormalizer
{
    /// <summary>
    /// Known multi-level effective top-level domains (eTLDs).
    /// A domain like 'bbc.co.uk' has eTLD 'co.uk' — base domain is 'bbc.co.uk' (3 labels).
    /// </summary>
    private static readonly HashSet<string> KnownMultiTlds = new(StringComparer.OrdinalIgnoreCase)
    {
        "co.uk", "org.uk", "gov.uk", "ac.uk", "net.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au",
        "co.nz", "net.nz", "org.nz", "govt.nz",
        "co.jp", "ne.jp", "or.jp", "go.jp", "ac.jp",
        "com.br", "org.br", "gov.br",
        "co.in", "net.in", "org.in", "gen.in",
        "com.sg", "edu.sg", "gov.sg",
        "github.io", "pages.dev", "vercel.app", "web.app",
        "ac.bd", "edu.bd", "com.bd", "net.bd",
        "co.za", "org.za", "gov.za",
    };

    /// <summary>
    /// Normalizes an input URL or raw hostname to a canonical lowercase hostname.
    /// Strips protocol, port, path, query, hash, trailing dot.
    /// </summary>
    public static string NormalizeHostname(string input)
    {
        if (string.IsNullOrWhiteSpace(input)) return string.Empty;

        var cleaned = input.Trim().ToLowerInvariant();

        // Try to parse as a full URI first
        if (cleaned.Contains("://"))
        {
            if (Uri.TryCreate(cleaned, UriKind.Absolute, out var uri))
            {
                cleaned = uri.Host;
            }
        }

        // Strip port (e.g. example.com:8080)
        var colonIdx = cleaned.IndexOf(':');
        if (colonIdx >= 0) cleaned = cleaned[..colonIdx];

        // Strip path (e.g. hostname/path)
        var slashIdx = cleaned.IndexOf('/');
        if (slashIdx >= 0) cleaned = cleaned[..slashIdx];

        // Strip trailing root dot (e.g. youtube.com. → youtube.com)
        cleaned = cleaned.TrimEnd('.');

        // Validate characters
        if (!IsValidHostname(cleaned)) return string.Empty;

        return cleaned;
    }

    /// <summary>
    /// Extracts the registrable base domain (eTLD+1) accounting for multi-level TLDs.
    /// Example: 'music.youtube.com' → 'youtube.com', 'm.news.bbc.co.uk' → 'bbc.co.uk'
    /// </summary>
    public static string GetBaseDomain(string hostname)
    {
        var norm = NormalizeHostname(hostname);
        if (string.IsNullOrEmpty(norm)) return string.Empty;

        var parts = norm.Split('.');
        if (parts.Length <= 1) return norm;

        // Check multi-level TLD (e.g. co.uk)
        if (parts.Length >= 3)
        {
            var lastTwo = string.Join('.', parts[^2..]);
            if (KnownMultiTlds.Contains(lastTwo))
                return string.Join('.', parts[^3..]);
        }

        return string.Join('.', parts[^2..]);
    }

    /// <summary>
    /// Determines if targetHostname matches the rulePattern.
    ///
    /// Match rules:
    ///   1. Exact: 'youtube.com' matches 'youtube.com'
    ///   2. Subdomain: 'www.youtube.com' matches 'youtube.com' (preceded by '.')
    ///   3. Wildcard: rulePattern starting with '*.' is stripped and treated as #2
    ///
    /// Critical security invariants:
    ///   - 'notyoutube.com' does NOT match 'youtube.com'
    ///   - 'youtube.com.attacker.com' does NOT match 'youtube.com'
    /// </summary>
    public static bool Matches(string targetHostname, string rulePattern)
    {
        var target = NormalizeHostname(targetHostname);
        var rule = NormalizeHostname(rulePattern.TrimStart('*').TrimStart('.'));

        if (string.IsNullOrEmpty(target) || string.IsNullOrEmpty(rule)) return false;

        // 1. Exact match
        if (string.Equals(target, rule, StringComparison.OrdinalIgnoreCase)) return true;

        // 2. Subdomain match — must be preceded by '.' (not just any suffix)
        if (target.EndsWith('.' + rule, StringComparison.OrdinalIgnoreCase)) return true;

        return false;
    }

    /// <summary>
    /// Finds the best (most-specific) matching rule from a list of policies.
    /// Longer rule domains take precedence over shorter parent domains.
    /// </summary>
    public static T? FindBestMatch<T>(string targetHostname, IEnumerable<T> rules, Func<T, string> getTarget)
    {
        T? bestMatch = default;
        int longestRuleLength = -1;

        foreach (var rule in rules)
        {
            var ruleTarget = getTarget(rule);
            if (!Matches(targetHostname, ruleTarget)) continue;

            var ruleNorm = NormalizeHostname(ruleTarget.TrimStart('*').TrimStart('.'));
            if (ruleNorm.Length > longestRuleLength)
            {
                longestRuleLength = ruleNorm.Length;
                bestMatch = rule;
            }
        }

        return bestMatch;
    }

    private static bool IsValidHostname(string hostname)
    {
        if (string.IsNullOrEmpty(hostname)) return false;
        foreach (var ch in hostname)
        {
            if (!char.IsLetterOrDigit(ch) && ch != '.' && ch != '-')
                return false;
        }
        return true;
    }
}
