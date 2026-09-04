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

    // Helper to check policy match
    const checkMatch = (policy) => {
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
      return { isMatched, matchedTarget };
    };

    // 2. Precedence Phase 1: Check Explicit BLOCK policies (limitSeconds <= 0)
    for (const policy of this.policies) {
      if (!policy.isEnabled || policy.enforcementMode !== 'BLOCK') continue;
      const limitSeconds = policy.limitSeconds || 0;
      if (limitSeconds > 0) continue; // Time limit evaluated in phase 2

      const { isMatched } = checkMatch(policy);
      if (isMatched) {
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
    }

    // 3. Precedence Phase 2: Check TIME_LIMIT budget exhaustion
    for (const policy of this.policies) {
      if (!policy.isEnabled) continue;
      const limitSeconds = policy.limitSeconds || policy.limit || 0;
      if (limitSeconds <= 0) continue;

      const { isMatched, matchedTarget } = checkMatch(policy);
      if (isMatched) {
        const usedSeconds = this.todayUsage[matchedTarget] || this.todayUsage[domain] || 0;
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
      }
    }

    // 4. Precedence Phase 3: Check Explicit ALLOW policies
    for (const policy of this.policies) {
      if (!policy.isEnabled || policy.enforcementMode !== 'ALLOW') continue;
      const { isMatched } = checkMatch(policy);
      if (isMatched) {
        return { action: 'ALLOW', reason: 'Explicitly Whitelisted', policyName: policy.name };
      }
    }

    // 5. Precedence Phase 4: TIME_LIMIT in-budget / warnings
    for (const policy of this.policies) {
      if (!policy.isEnabled) continue;
      const limitSeconds = policy.limitSeconds || policy.limit || 0;
      if (limitSeconds <= 0) continue;

      const { isMatched, matchedTarget } = checkMatch(policy);
      if (isMatched) {
        const usedSeconds = this.todayUsage[matchedTarget] || this.todayUsage[domain] || 0;
        const remainingSeconds = Math.max(0, limitSeconds - usedSeconds);
        const percentage = Math.min(100, Math.round((usedSeconds / limitSeconds) * 100));

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
