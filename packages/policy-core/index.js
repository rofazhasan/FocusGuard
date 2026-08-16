/**
 * FocusGuard Policy Core Engine
 * Deterministic local policy evaluation pipeline, monotonic version validation,
 * schedule resolution, attention budget limit evaluation, and conflict resolution.
 */

const DomainEngine = require('../domain-engine/index.js');
const { TargetType, ActionType, DecisionType } = require('../shared-types/index.js');

class PolicyCoreEngine {
  /**
   * Validates policy version monotonicity.
   * Never allow downgrade (e.g. v42 -> v41).
   * @param {number} currentVersion 
   * @param {number} incomingVersion 
   * @returns {boolean}
   */
  static validateVersionTransition(currentVersion, incomingVersion) {
    if (typeof incomingVersion !== 'number' || isNaN(incomingVersion)) return false;
    if (typeof currentVersion !== 'number' || isNaN(currentVersion)) return true;
    return incomingVersion >= currentVersion;
  }

  /**
   * Checks if current time is within a scheduled window.
   * Format: { days: [1,2,3,4,5], start: "09:00", end: "17:00" } (days: 0=Sun, 6=Sat)
   * @param {object} schedule 
   * @param {Date} [now]
   * @returns {boolean}
   */
  static isScheduleActive(schedule, now = new Date()) {
    if (!schedule) return true; // No schedule means always active

    const day = now.getDay();
    if (Array.isArray(schedule.days) && schedule.days.length > 0 && !schedule.days.includes(day)) {
      return false;
    }

    if (schedule.start && schedule.end) {
      const currentMinutes = now.getHours() * 60 + now.getMinutes();
      const [sH, sM] = schedule.start.split(':').map(Number);
      const [eH, eM] = schedule.end.split(':').map(Number);
      const startMinutes = sH * 60 + sM;
      const endMinutes = eH * 60 + eM;

      if (startMinutes <= endMinutes) {
        return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
      } else {
        // Overnight window (e.g. 22:00 to 07:00)
        return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
      }
    }

    return true;
  }

  /**
   * Main Evaluation Pipeline
   * Evaluates a resource access request against local policies and usage context.
   * @param {object} params
   * @param {string} params.targetType - 'DOMAIN' | 'APP' | 'CATEGORY' | 'URL'
   * @param {string} params.target - Hostname, app bundle/package, or category
   * @param {string} [params.deviceId] - Device ID making the request
   * @param {Array<object>} params.policies - Active policy list
   * @param {number} [params.currentUsageSeconds] - Accumulated usage today in seconds
   * @param {Date} [params.now]
   * @returns {object} Decision object
   */
  static evaluate({ targetType, target, deviceId, policies, currentUsageSeconds = 0, now = new Date() }) {
    if (!policies || !Array.isArray(policies) || policies.length === 0) {
      return {
        decision: DecisionType.ALLOW,
        reason: 'NO_POLICIES_DEFINED',
        policyId: null,
        policyVersion: 0
      };
    }

    // 1. Filter applicable policies by targetType and deviceId
    const applicable = policies.filter(p => {
      if (p.targetType !== targetType) return false;
      if (p.devices && Array.isArray(p.devices) && p.devices.length > 0) {
        if (deviceId && !p.devices.includes(deviceId)) return false;
      }
      return true;
    });

    if (applicable.length === 0) {
      return {
        decision: DecisionType.ALLOW,
        reason: 'NO_MATCHING_POLICY',
        policyId: null,
        policyVersion: 0
      };
    }

    // 2. Filter matching policies
    const matchedPolicies = [];
    for (const policy of applicable) {
      let isMatch = false;
      if (targetType === TargetType.DOMAIN || targetType === 'DOMAIN') {
        isMatch = DomainEngine.matches(target, policy.target);
      } else if (targetType === TargetType.APP || targetType === 'APP') {
        isMatch = policy.target.toLowerCase() === target.toLowerCase();
      } else if (targetType === TargetType.CATEGORY || targetType === 'CATEGORY') {
        isMatch = policy.target.toLowerCase() === target.toLowerCase();
      }

      if (isMatch) {
        matchedPolicies.push(policy);
      }
    }

    if (matchedPolicies.length === 0) {
      return {
        decision: DecisionType.ALLOW,
        reason: 'NO_MATCHING_RULES',
        policyId: null,
        policyVersion: 0
      };
    }

    // 3. Sort by priority (highest priority first)
    matchedPolicies.sort((a, b) => (b.priority || 0) - (a.priority || 0));

    // 4. Evaluate each policy according to action, schedule, and limits
    for (const policy of matchedPolicies) {
      const scheduleActive = this.isScheduleActive(policy.schedule, now);
      if (!scheduleActive) {
        continue; // Policy schedule is inactive at this time
      }

      // Explicit ALLOW action overrides lower priority blocks
      if (policy.action === ActionType.ALLOW || policy.action === 'ALLOW') {
        return {
          decision: DecisionType.ALLOW,
          reason: 'EXPLICIT_ALLOW_RULE',
          policyId: policy.id,
          policyVersion: policy.version
        };
      }

      // Explicit unconditional BLOCK action
      if (policy.action === ActionType.BLOCK || policy.action === 'BLOCK' ||
          policy.action === ActionType.NETWORK_BLOCK || policy.action === 'NETWORK_BLOCK') {
        return {
          decision: DecisionType.BLOCK,
          reason: 'SCHEDULED_BLOCK_ACTIVE',
          policyId: policy.id,
          policyVersion: policy.version
        };
      }

      // TIME_LIMIT or APP_LIMIT evaluation
      if (policy.action === ActionType.TIME_LIMIT || policy.action === 'TIME_LIMIT' ||
          policy.action === ActionType.APP_LIMIT || policy.action === 'APP_LIMIT') {
        const limitSeconds = policy.limit || 0;
        
        if (currentUsageSeconds >= limitSeconds) {
          return {
            decision: DecisionType.BLOCK,
            reason: 'TIME_LIMIT_EXCEEDED',
            policyId: policy.id,
            policyVersion: policy.version,
            usedSeconds: currentUsageSeconds,
            limitSeconds: limitSeconds
          };
        } else if (currentUsageSeconds >= limitSeconds * 0.9) {
          return {
            decision: DecisionType.WARN,
            reason: 'TIME_LIMIT_90_PERCENT',
            policyId: policy.id,
            policyVersion: policy.version,
            usedSeconds: currentUsageSeconds,
            limitSeconds: limitSeconds
          };
        } else if (currentUsageSeconds >= limitSeconds * 0.8) {
          return {
            decision: DecisionType.WARN,
            reason: 'TIME_LIMIT_80_PERCENT',
            policyId: policy.id,
            policyVersion: policy.version,
            usedSeconds: currentUsageSeconds,
            limitSeconds: limitSeconds
          };
        } else {
          return {
            decision: DecisionType.ALLOW,
            reason: 'WITHIN_TIME_LIMIT',
            policyId: policy.id,
            policyVersion: policy.version,
            usedSeconds: currentUsageSeconds,
            limitSeconds: limitSeconds
          };
        }
      }

      // Focus Mode session
      if (policy.action === ActionType.FOCUS || policy.action === 'FOCUS') {
        return {
          decision: DecisionType.BLOCK,
          reason: 'FOCUS_MODE_ACTIVE',
          policyId: policy.id,
          policyVersion: policy.version
        };
      }
    }

    // Default fallback
    return {
      decision: DecisionType.ALLOW,
      reason: 'DEFAULT_ALLOW',
      policyId: null,
      policyVersion: 0
    };
  }
}

module.exports = PolicyCoreEngine;
