/**
 * FocusGuard Browser Extension — DeclarativeNetRequest (DNR) Policy Compiler
 * 
 * Compiles cloud & local attention policies into native browser declarative rulesets:
 * - DYNAMIC RULES: Long-lived user policies and daily budget limits
 * - SESSION RULES: Temporary high-priority Focus Mode lockdowns
 * 
 * Complies with Chrome (MV3) and Firefox WebExtensions DNR standards.
 */

class DNRPolicyCompiler {
  /**
   * Compiles an array of FocusGuard policies into declarativeNetRequest Rule objects.
   * 
   * Precedence priorities:
   * - Priority 100: Explicit ALLOW rules (whitelist overrides)
   * - Priority 50: Explicit BLOCK & exhausted budget rules
   * - Priority 20: Category BLOCK rules
   * 
   * @param {Array} policies - Array of FocusGuard policy objects
   * @param {Object} todayUsage - Map of target -> consumed seconds
   * @returns {Array<Object>} Array of DNR Rule objects
   */
  static compileDynamicRules(policies, todayUsage = {}) {
    const rules = [];
    let ruleId = 1;

    for (const policy of policies || []) {
      if (!policy.isEnabled) continue;

      const isAllow = policy.enforcementMode === 'ALLOW';
      const limitSeconds = policy.limitSeconds || 0;
      const priority = isAllow ? 100 : (policy.priority || 50);

      for (const target of policy.targets || []) {
        let domain = '';
        if (target.targetType === 'WEBSITE' || target.targetType === 'DOMAIN') {
          domain = target.targetValue.trim().toLowerCase().replace(/^www\./, '');
        } else if (target.targetType === 'CATEGORY') {
          // Category compilation expanded below
          continue;
        }

        if (!domain) continue;

        // If time-limited, only enforce DNR block if usage meets or exceeds limit
        if (!isAllow && limitSeconds > 0) {
          const usedSec = todayUsage[domain] || todayUsage[target.targetValue] || 0;
          if (usedSec < limitSeconds) {
            continue; // Under budget; evaluated by background active tracker
          }
        }

        if (isAllow) {
          // Declarative ALLOW rule (type: "allow")
          rules.push({
            id: ruleId++,
            priority: priority,
            action: { type: 'allow' },
            condition: {
              urlFilter: `||${domain}^`,
              resourceTypes: ['main_frame', 'sub_frame']
            }
          });
        } else {
          // Declarative REDIRECT / BLOCK rule
          const blockUrl = typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.getURL
            ? chrome.runtime.getURL(`pages/block.html?target=${encodeURIComponent(domain)}&reason=Daily%20attention%20budget%20reached&policy=${encodeURIComponent(policy.name)}`)
            : `/pages/block.html?target=${encodeURIComponent(domain)}`;

          rules.push({
            id: ruleId++,
            priority: priority,
            action: {
              type: 'redirect',
              redirect: { url: blockUrl }
            },
            condition: {
              urlFilter: `||${domain}^`,
              resourceTypes: ['main_frame']
            }
          });
        }
      }
    }

    return rules;
  }

  /**
   * Compiles temporary Focus Session lockdown into session-scoped DNR rules.
   * Focus Mode operates with top priority (200) to override general access.
   * 
   * @param {Object} focusSession - Active focus session configuration
   * @returns {Array<Object>}
   */
  static compileSessionRules(focusSession) {
    if (!focusSession || !focusSession.isActive) {
      return [];
    }

    const rules = [];
    let ruleId = 1000;

    // 1. Explicit allowlist for focus mode (Priority 300)
    const allowedDomains = focusSession.allowedDomains || ['github.com', 'stackoverflow.com', 'canvas.instructure.com'];
    for (const domain of allowedDomains) {
      rules.push({
        id: ruleId++,
        priority: 300,
        action: { type: 'allow' },
        condition: {
          urlFilter: `||${domain}^`,
          resourceTypes: ['main_frame', 'sub_frame']
        }
      });
    }

    // 2. Block distractors during focus session (Priority 200)
    const blockedDistractors = focusSession.blockedDomains || [
      'youtube.com', 'netflix.com', 'twitch.tv', 'instagram.com',
      'facebook.com', 'twitter.com', 'x.com', 'reddit.com', 'tiktok.com'
    ];

    const blockUrl = typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.getURL
      ? chrome.runtime.getURL(`pages/block.html?target=Distraction&reason=Remote%20Focus%20Lockdown%20Active&policy=${encodeURIComponent(focusSession.name || 'Focus Session')}`)
      : `/pages/block.html?target=Distraction`;

    for (const domain of blockedDistractors) {
      rules.push({
        id: ruleId++,
        priority: 200,
        action: {
          type: 'redirect',
          redirect: { url: blockUrl }
        },
        condition: {
          urlFilter: `||${domain}^`,
          resourceTypes: ['main_frame']
        }
      });
    }

    return rules;
  }

  /**
   * Synchronizes compiled rules directly with browser declarative engine.
   */
  static async syncWithBrowser(dynamicRules, sessionRules = []) {
    if (typeof chrome === 'undefined' || !chrome.declarativeNetRequest) {
      return false;
    }

    try {
      // 1. Update Dynamic Rules
      const existingDynamic = await chrome.declarativeNetRequest.getDynamicRules();
      const removeRuleIds = existingDynamic.map(r => r.id);

      await chrome.declarativeNetRequest.updateDynamicRules({
        removeRuleIds: removeRuleIds,
        addRules: dynamicRules
      });

      // 2. Update Session Rules
      if (chrome.declarativeNetRequest.getSessionRules) {
        const existingSession = await chrome.declarativeNetRequest.getSessionRules();
        const removeSessionIds = existingSession.map(r => r.id);

        await chrome.declarativeNetRequest.updateSessionRules({
          removeRuleIds: removeSessionIds,
          addRules: sessionRules
        });
      }

      console.log(`[FocusGuard DNR] Browser request engine updated: ${dynamicRules.length} dynamic, ${sessionRules.length} session rules active.`);
      return true;
    } catch (err) {
      console.error('[FocusGuard DNR] Failed to update browser rules:', err);
      return false;
    }
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { DNRPolicyCompiler };
}
