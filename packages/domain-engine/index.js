/**
 * FocusGuard Domain Engine Package
 * Enterprise-grade hostname normalization, Public Suffix List aware hierarchy, and rule matching.
 * NEVER uses raw substring or url.includes() matching.
 */

// Multi-level effective top-level domains (eTLDs) subset for precision matching
const KNOWN_MULTI_TLDS = new Set([
  'co.uk', 'org.uk', 'gov.uk', 'ac.uk', 'net.uk',
  'com.au', 'net.au', 'org.au', 'edu.au', 'gov.au',
  'co.nz', 'net.nz', 'org.nz', 'govt.nz',
  'co.jp', 'ne.jp', 'or.jp', 'go.jp', 'ac.jp',
  'com.br', 'org.br', 'gov.br',
  'co.in', 'net.in', 'org.in', 'gen.in',
  'com.sg', 'edu.sg', 'gov.sg',
  'github.io', 'pages.dev', 'vercel.app', 'web.app'
]);

class DomainEngine {
  /**
   * Normalize an input URL or raw hostname to a clean, canonical hostname.
   * Strips protocol, port, userinfo, trailing dot, query, hash, and converts to lowercase.
   * @param {string} input - URL or hostname string
   * @returns {string} canonical hostname
   */
  static normalizeHostname(input) {
    if (!input || typeof input !== 'string') return '';
    let cleaned = input.trim().toLowerCase();

    // If input lacks protocol, prepend dummy for URL parsing
    if (!cleaned.includes('://')) {
      // Strip path/query if present
      const slashIdx = cleaned.indexOf('/');
      if (slashIdx !== -1) cleaned = cleaned.substring(0, slashIdx);
      const queryIdx = cleaned.indexOf('?');
      if (queryIdx !== -1) cleaned = cleaned.substring(0, queryIdx);
      const hashIdx = cleaned.indexOf('#');
      if (hashIdx !== -1) cleaned = cleaned.substring(0, hashIdx);
    } else {
      try {
        const parsed = new URL(cleaned);
        cleaned = parsed.hostname;
      } catch (e) {
        // Fallback cleanup
        cleaned = cleaned.replace(/^[a-zA-Z]+:\/\//, '').split('/')[0];
      }
    }

    // Strip port if present (e.g. localhost:8080 or example.com:443)
    cleaned = cleaned.split(':')[0];

    // Strip trailing dot (DNS root)
    if (cleaned.endsWith('.')) {
      cleaned = cleaned.slice(0, -1);
    }

    // Validate valid hostname characters
    if (!/^[a-z0-9.-]+$/.test(cleaned)) {
      return '';
    }

    return cleaned;
  }

  /**
   * Extracts the base registrable domain (eTLD+1) respecting multi-level suffixes.
   * @param {string} hostname 
   * @returns {string} base domain (e.g., 'youtube.com', 'bbc.co.uk')
   */
  static getBaseDomain(hostname) {
    const norm = this.normalizeHostname(hostname);
    if (!norm) return '';
    const parts = norm.split('.');
    if (parts.length <= 1) return norm;

    // Check multi-level TLD
    if (parts.length >= 3) {
      const lastTwo = parts.slice(-2).join('.');
      if (KNOWN_MULTI_TLDS.has(lastTwo)) {
        return parts.slice(-3).join('.');
      }
    }

    return parts.slice(-2).join('.');
  }

  /**
   * Deterministic matching check: determines if targetHostname matches the rulePattern.
   * Exact match OR full subdomain match.
   * Example:
   *   rule: "youtube.com" matches "youtube.com", "www.youtube.com", "m.youtube.com"
   *   rule: "youtube.com" DOES NOT match "notyoutube.com" or "youtube.com.attacker.com"
   * @param {string} targetHostname - The actual visited hostname
   * @param {string} rulePattern - The policy target domain / pattern
   * @returns {boolean}
   */
  static matches(targetHostname, rulePattern) {
    const target = this.normalizeHostname(targetHostname);
    let rule = this.normalizeHostname(rulePattern.replace(/^\*\./, '')); // Strip wildcard prefix if present

    if (!target || !rule) return false;

    // 1. Exact match
    if (target === rule) return true;

    // 2. Subdomain match (must be preceded by a dot)
    if (target.endsWith('.' + rule)) return true;

    return false;
  }

  /**
   * Finds the best matching rule from a list of rules for a given hostname.
   * Longer/more specific domain rules take precedence over broader parent domain rules.
   * @param {string} targetHostname 
   * @param {Array<{target: string, [key: string]: any}>} rules 
   * @returns {object|null}
   */
  static findBestMatch(targetHostname, rules) {
    const target = this.normalizeHostname(targetHostname);
    if (!target || !Array.isArray(rules)) return null;

    let bestMatch = null;
    let longestRuleLength = -1;

    for (const rule of rules) {
      if (!rule || !rule.target) continue;
      if (this.matches(target, rule.target)) {
        const ruleNorm = this.normalizeHostname(rule.target.replace(/^\*\./, ''));
        if (ruleNorm.length > longestRuleLength) {
          longestRuleLength = ruleNorm.length;
          bestMatch = rule;
        }
      }
    }

    return bestMatch;
  }
}

module.exports = DomainEngine;
