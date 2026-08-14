/**
 * FocusGuard Browser Extension — Domain Matcher Core
 * 
 * Provides safe, hostname-aware domain normalization, exact matching,
 * subdomain matching, and URL pattern matching without insecure substring inclusion.
 */

class DomainMatcher {
  /**
   * Normalizes a raw URL or domain string into a clean hostname.
   * Strips protocol (http://, https://, ws://), default ports, paths, queries, hashes, trailing dots.
   * Converts to lowercase and trims whitespace.
   * 
   * @param {string} raw - The raw URL or domain string.
   * @returns {string} Clean normalized hostname.
   */
  static normalizeDomain(raw) {
    if (!raw || typeof raw !== 'string') return '';
    let str = raw.trim().toLowerCase();

    // Strip protocol
    const protoIdx = str.indexOf('://');
    if (protoIdx !== -1) {
      str = str.substring(protoIdx + 3);
    }

    // Strip path, query parameters, hash, or port
    const pathIdx = str.search(/[/?#:]/);
    if (pathIdx !== -1) {
      str = str.substring(0, pathIdx);
    }

    // Strip trailing dots (FQDN format)
    str = str.replace(/\.+$/, '');

    return str;
  }

  /**
   * Known Multi-Level Public Suffixes (PSL)
   */
  static PUBLIC_SUFFIXES = new Set([
    'co.uk', 'org.uk', 'gov.uk', 'ac.uk',
    'com.bd', 'edu.bd', 'gov.bd', 'org.bd', 'ac.bd',
    'com.au', 'net.au', 'org.au', 'edu.au',
    'co.jp', 'ne.jp', 'ac.jp',
    'co.in', 'net.in', 'org.in',
    'com.br', 'org.br',
    'github.io', 'gitlab.io', 'vercel.app', 'netlify.app', 'pages.dev', 'appspot.com'
  ]);

  /**
   * Extracts the registrable domain (e.g. "bbc.co.uk" from "m.news.bbc.co.uk" or "team.github.io" from "a.b.team.github.io").
   * @param {string} raw - Domain or URL
   * @returns {string} Registrable apex domain
   */
  static getRegistrableDomain(raw) {
    const host = this.normalizeDomain(raw).replace(/^www\./, '');
    if (!host) return '';

    const parts = host.split('.');
    if (parts.length <= 2) return host;

    // Check two-part TLDs like co.uk, com.bd, github.io
    const lastTwo = parts.slice(-2).join('.');
    if (this.PUBLIC_SUFFIXES.has(lastTwo)) {
      return parts.slice(-3).join('.');
    }

    // Standard 1-part TLD (.com, .org, .net, etc.)
    return parts.slice(-2).join('.');
  }

  /**
   * Evaluates if a candidate hostname matches a target domain policy.
   * 
   * Rules:
   * 1. Exact match: "youtube.com" matches "youtube.com"
   * 2. www normalization: "www.youtube.com" matches "youtube.com"
   * 3. Subdomain match: "m.youtube.com" or "music.youtube.com" matches "youtube.com"
   * 4. Multi-level PSL match: "student.portal.du.ac.bd" matches "du.ac.bd"
   * 5. Insecure substring protection: "notyoutube.com" or "youtube.company.com" (unless subdomain) does NOT match "youtube.com"
   * 
   * @param {string} candidate - The visited domain or URL.
   * @param {string} target - The policy target domain.
   * @returns {boolean} True if matched according to strict domain hierarchy.
   */
  static isDomainMatch(candidate, target) {
    const candidateHost = this.normalizeDomain(candidate);
    const targetHost = this.normalizeDomain(target);

    if (!candidateHost || !targetHost) return false;

    const cleanCandidate = candidateHost.startsWith('www.') ? candidateHost.substring(4) : candidateHost;
    const cleanTarget = targetHost.startsWith('www.') ? targetHost.substring(4) : targetHost;

    // Exact match
    if (cleanCandidate === cleanTarget) {
      return true;
    }

    // Strict subdomain match (must be preceded by a dot)
    if (cleanCandidate.endsWith('.' + cleanTarget)) {
      return true;
    }

    // PSL-aware root match
    if (this.getRegistrableDomain(cleanCandidate) === this.getRegistrableDomain(cleanTarget) && cleanTarget === this.getRegistrableDomain(cleanTarget)) {
      return true;
    }

    return false;
  }

  /**
   * Matches a full URL against a URL pattern policy.
   * Supports DOMAIN, SUBDOMAIN, and URL_PATTERN rules.
   * 
   * @param {string} fullUrl - The complete URL string.
   * @param {string} pattern - The policy pattern (e.g. "reddit.com/r/gaming", "youtube.com/shorts*").
   * @returns {boolean}
   */
  static isUrlPatternMatch(fullUrl, pattern) {
    if (!fullUrl || !pattern) return false;

    const cleanUrl = fullUrl.trim().toLowerCase();
    const cleanPattern = pattern.trim().toLowerCase();

    // Check if pattern contains path components
    const slashIdx = cleanPattern.indexOf('/');
    if (slashIdx === -1) {
      // Pure domain match
      return this.isDomainMatch(cleanUrl, cleanPattern);
    }

    const patternHost = cleanPattern.substring(0, slashIdx);
    const patternPath = cleanPattern.substring(slashIdx);

    try {
      const parsedUrl = new URL(cleanUrl.startsWith('http') ? cleanUrl : `https://${cleanUrl}`);
      const urlHost = parsedUrl.hostname.toLowerCase();
      const urlPath = parsedUrl.pathname.toLowerCase();

      // Host must match
      if (!this.isDomainMatch(urlHost, patternHost)) {
        return false;
      }

      // Path matching: supports wildcard suffix
      if (patternPath.endsWith('*')) {
        const prefix = patternPath.slice(0, -1);
        return urlPath.startsWith(prefix);
      }

      return urlPath === patternPath || urlPath.startsWith(patternPath.endsWith('/') ? patternPath : patternPath + '/');
    } catch {
      return false;
    }
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { DomainMatcher };
}
