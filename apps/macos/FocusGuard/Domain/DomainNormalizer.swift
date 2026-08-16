// FocusGuard macOS Agent — Domain Layer
// PSL-aware hostname normalizer and domain matching engine.
// Port of packages/domain-engine into Swift — same precision guarantees.
// NEVER uses contains() for domain matching.

import Foundation

public struct DomainNormalizer {
    /// Known multi-level effective top-level domains (eTLDs).
    private static let knownMultiTlds: Set<String> = [
        "co.uk", "org.uk", "gov.uk", "ac.uk", "net.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au",
        "co.nz", "net.nz", "org.nz", "govt.nz",
        "co.jp", "ne.jp", "or.jp", "go.jp", "ac.jp",
        "com.br", "org.br", "gov.br",
        "co.in", "net.in", "org.in", "gen.in",
        "com.sg", "edu.sg", "gov.sg",
        "github.io", "pages.dev", "vercel.app", "web.app",
        "ac.bd", "edu.bd", "com.bd", "net.bd",
        "co.za", "org.za", "gov.za"
    ]

    /// Normalizes an input URL or raw hostname to a canonical lowercase hostname.
    public static func normalizeHostname(_ input: String) -> String {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return "" }

        // Parse as URL if protocol present
        if cleaned.contains("://") {
            if let url = URL(string: cleaned), let host = url.host {
                cleaned = host
            }
        }

        // Strip port (e.g. example.com:8080)
        if let colonIdx = cleaned.firstIndex(of: ":") {
            cleaned = String(cleaned[..<colonIdx])
        }

        // Strip path (e.g. hostname/path)
        if let slashIdx = cleaned.firstIndex(of: "/") {
            cleaned = String(cleaned[..<slashIdx])
        }

        // Strip trailing root dots
        while cleaned.hasSuffix(".") {
            cleaned.removeLast()
        }

        // Validate basic hostname characters
        guard isValidHostname(cleaned) else { return "" }

        return cleaned
    }

    /// Extracts the registrable base domain (eTLD+1) accounting for multi-level TLDs.
    public static func getBaseDomain(_ hostname: String) -> String {
        let norm = normalizeHostname(hostname)
        guard !norm.isEmpty else { return "" }

        let parts = norm.split(separator: ".").map(String.init)
        guard parts.count > 1 else { return norm }

        // Check multi-level TLD
        if parts.count >= 3 {
            let lastTwo = parts.suffix(2).joined(separator: ".")
            if knownMultiTlds.contains(lastTwo) {
                return parts.suffix(3).joined(separator: ".")
            }
        }

        return parts.suffix(2).joined(separator: ".")
    }

    /// Determines if targetHostname matches the rulePattern.
    ///
    /// Match rules:
    ///   1. Exact: 'youtube.com' matches 'youtube.com'
    ///   2. Subdomain: 'www.youtube.com' matches 'youtube.com' (must be preceded by '.')
    ///   3. Wildcard: '*.youtube.com' stripped to 'youtube.com'
    ///
    /// Critical security invariants:
    ///   - 'notyoutube.com' does NOT match 'youtube.com'
    ///   - 'youtube.com.attacker.com' does NOT match 'youtube.com'
    public static func matches(target: String, rulePattern: String) -> Bool {
        let cleanTarget = normalizeHostname(target)
        var cleanRule = rulePattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while cleanRule.hasPrefix("*") || cleanRule.hasPrefix(".") {
            cleanRule.removeFirst()
        }
        cleanRule = normalizeHostname(cleanRule)

        guard !cleanTarget.isEmpty, !cleanRule.isEmpty else { return false }

        // 1. Exact match
        if cleanTarget == cleanRule { return true }

        // 2. Subdomain match — strictly preceded by '.'
        if cleanTarget.hasSuffix("." + cleanRule) { return true }

        return false
    }

    private static func isValidHostname(_ hostname: String) -> Bool {
        guard !hostname.isEmpty else { return false }
        for ch in hostname {
            if !ch.isLetter && !ch.isNumber && ch != "." && ch != "-" {
                return false
            }
        }
        return true
    }
}
