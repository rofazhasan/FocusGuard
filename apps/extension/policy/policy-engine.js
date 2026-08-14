/**
 * FocusGuard Browser Extension — Policy Engine Core
 * 
 * Evaluates website visits against local cached policies, focus sessions,
 * daily time limits, schedules, and categories with deterministic precedence.
 */

class ExtensionPolicyEngine {
  constructor(domainMatcher) {
    this.matcher = domainMatcher || (typeof DomainMatcher !== 'undefined' ? DomainMatcher : null);
    this.policies = [];
    this.focusSession = null;
    this.todayUsage = {}; // domain/target -> seconds
    this.categoryDatabase = {
      'youtube.com': 'VIDEO',
      'netflix.com': 'VIDEO',
      'twitch.tv': 'VIDEO',
      'vimeo.com': 'VIDEO',
      'tiktok.com': 'VIDEO',
      'instagram.com': 'SOCIAL',
      'facebook.com': 'SOCIAL',
      'twitter.com': 'SOCIAL',
      'x.com': 'SOCIAL',
      'reddit.com': 'SOCIAL',
      'threads.net': 'SOCIAL',
      'snapchat.com': 'SOCIAL',
      'steampowered.com': 'GAMING',
      'roblox.com': 'GAMING',
      'epicgames.com': 'GAMING',
      'discord.com': 'GAMING',
      'chess.com': 'GAMING',
      'github.com': 'EDUCATION',
      'stackoverflow.com': 'EDUCATION',
      'docs.google.com': 'WORK'
    };
  }

  setPolicies(policies) {
    this.policies = Array.isArray(policies) ? policies : [];
  }

  setFocusSession(session) {
    this.focusSession = session && session.isActive ? session : null;
  }

  setTodayUsage(usageMap) {
    this.todayUsage = usageMap || {};
  }

  updateUsage(targetValue, deltaSeconds) {
    const current = this.todayUsage[targetValue] || 0;
    this.todayUsage[targetValue] = current + deltaSeconds;
  }

  getCategory(domain) {
    const clean = this.matcher ? this.matcher.normalizeDomain(domain) : domain.toLowerCase();
    for (const [d, cat] of Object.entries(this.categoryDatabase)) {
      if (this.matcher ? this.matcher.isDomainMatch(clean, d) : clean.endsWith(d)) {
        return cat;
      }
    }
    return 'UNCATEGORIZED';
  }

  /**
   * Evaluates if a given URL or domain should be blocked or warned.
   * 
   * Returns:
   * {
   *   action: 'ALLOW' | 'BLOCK' | 'WARN',
   *   reason: string,
   *   policyName: string,
   *   limitMinutes: number,
   *   usedMinutes: number,
   *   remainingMinutes: number,
   *   percentageUsed: number,
   *   nextReset: string
   * }
   */
  evaluate(url) {
    const domain = this.matcher ? this.matcher.normalizeDomain(url) : url;
    const category = this.getCategory(domain);

    // 1. Check Active Focus Session (Highest Enforcement Priority)
    if (this.focusSession && this.focusSession.isActive) {
      const allowedCategories = this.focusSession.allowedCategories || ['EDUCATION', 'WORK'];
      const allowedDomains = this.focusSession.allowedDomains || ['github.com', 'stackoverflow.com'];

      const isExplicitlyAllowed = allowedDomains.some(d => this.matcher.isDomainMatch(domain, d));
      const isCategoryAllowed = allowedCategories.includes(category);

      if (!isExplicitlyAllowed && !isCategoryAllowed && (category === 'SOCIAL' || category === 'VIDEO' || category === 'GAMING')) {
        return {
          action: 'BLOCK',
          reason: 'Remote Focus Lockdown Active',
          policyName: this.focusSession.name || 'Active Focus Session',
          limitMinutes: this.focusSession.durationMinutes || 45,
          usedMinutes: this.focusSession.durationMinutes || 45,
          remainingMinutes: 0,
          percentageUsed: 100,
          category: category,
          nextReset: 'Upon Focus Session Completion'
        };
      }
    }

    // 2. Precedence Phase: Check Explicit ALLOW policies first
    for (const policy of this.policies) {
      if (!policy.isEnabled || policy.enforcementMode !== 'ALLOW') continue;
      for (const target of policy.targets || []) {
        if (target.targetType === 'WEBSITE' || target.targetType === 'DOMAIN') {
          if (this.matcher.isDomainMatch(domain, target.targetValue)) {
            return { action: 'ALLOW', reason: 'Explicitly Whitelisted', policyName: policy.name };
          }
        }
      }
    }

    // 3. Evaluate BLOCK and TIME_LIMIT policies
    for (const policy of this.policies) {
      if (!policy.isEnabled) continue;

      let isMatched = false;
      let matchedTarget = null;

      for (const target of policy.targets || []) {
        if (target.targetType === 'WEBSITE' || target.targetType === 'DOMAIN') {
          if (this.matcher.isDomainMatch(domain, target.targetValue)) {
            isMatched = true;
            matchedTarget = target.targetValue;
            break;
          }
        } else if (target.targetType === 'CATEGORY') {
          if (target.targetValue.toUpperCase() === category.toUpperCase()) {
            isMatched = true;
            matchedTarget = category;
            break;
          }
        } else if (target.targetType === 'URL_PATTERN') {
          if (this.matcher.isUrlPatternMatch(url, target.targetValue)) {
            isMatched = true;
            matchedTarget = target.targetValue;
            break;
          }
        }
      }

      if (!isMatched) continue;

      // Policy Rule: Immediate BLOCK without limit
      const limitSeconds = policy.limitSeconds || 0;
      if (policy.enforcementMode === 'BLOCK' && limitSeconds <= 0) {
        return {
          action: 'BLOCK',
          reason: 'Domain Restricted by Policy',
          policyName: policy.name,
          limitMinutes: 0,
          usedMinutes: 0,
          remainingMinutes: 0,
          percentageUsed: 100,
          category: category,
          nextReset: '12:00 AM'
        };
      }

      // Policy Rule: TIME_LIMIT (Attention Budget)
      if (limitSeconds > 0) {
        const usedSeconds = this.todayUsage[matchedTarget] || this.todayUsage[domain] || 0;
        const remainingSeconds = Math.max(0, limitSeconds - usedSeconds);
        const percentage = Math.min(100, Math.round((usedSeconds / limitSeconds) * 100));

        if (usedSeconds >= limitSeconds) {
          return {
            action: 'BLOCK',
            reason: 'Daily attention budget reached.',
            policyName: policy.name,
            limitMinutes: Math.round(limitSeconds / 60),
            usedMinutes: Math.round(usedSeconds / 60),
            remainingMinutes: 0,
            percentageUsed: 100,
            category: category,
            nextReset: '12:00 AM'
          };
        }

        if (percentage >= 90) {
          return {
            action: 'WARN',
            reason: `3 minutes remaining (${percentage}% of budget used)`,
            policyName: policy.name,
            limitMinutes: Math.round(limitSeconds / 60),
            usedMinutes: Math.round(usedSeconds / 60),
            remainingMinutes: Math.round(remainingSeconds / 60),
            percentageUsed: percentage,
            category: category,
            nextReset: '12:00 AM'
          };
        } else if (percentage >= 80) {
          return {
            action: 'WARN',
            reason: `6 minutes remaining (${percentage}% of budget used)`,
            policyName: policy.name,
            limitMinutes: Math.round(limitSeconds / 60),
            usedMinutes: Math.round(usedSeconds / 60),
            remainingMinutes: Math.round(remainingSeconds / 60),
            percentageUsed: percentage,
            category: category,
            nextReset: '12:00 AM'
          };
        }
      }
    }

    return { action: 'ALLOW', reason: 'No blocking policy active' };
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { ExtensionPolicyEngine };
}
