/**
 * FocusGuard Event Model Package
 * Formal event schemas, structured event creators, and idempotency validators.
 */

const { EventType } = require('../shared-types/index.js');
const CryptoEngine = require('../crypto/index.js');

class EventFactory {
  /**
   * Creates a standardized FocusGuard system event.
   * @param {object} params
   * @param {string} params.type - EventType enum value
   * @param {string} params.deviceId - Enrolled device identifier
   * @param {number} [params.policyVersion] - Current policy version
   * @param {object} params.payload - Event-specific data
   * @returns {object} Standardized event envelope
   */
  static createEvent({ type, deviceId, policyVersion = 1, payload = {} }) {
    if (!EventType[type]) {
      throw new Error(`Invalid EventType: ${type}`);
    }

    const timestamp = Date.now();
    const eventId = `evt_${CryptoEngine.generateId(12)}`;

    return {
      eventId,
      type,
      deviceId,
      policyVersion,
      timestamp,
      payload
    };
  }

  static createDomainBlockedEvent({ deviceId, policyVersion, domain, policyId, reason, usedSeconds, limitSeconds }) {
    return this.createEvent({
      type: EventType.DOMAIN_BLOCKED,
      deviceId,
      policyVersion,
      payload: {
        domain,
        policyId,
        reason,
        usedSeconds,
        limitSeconds,
        action: 'BLOCK'
      }
    });
  }

  static createAppLimitReachedEvent({ deviceId, policyVersion, target, policyId, usedSeconds, limitSeconds }) {
    return this.createEvent({
      type: EventType.APP_LIMIT_REACHED,
      deviceId,
      policyVersion,
      payload: {
        target,
        policyId,
        usedSeconds,
        limitSeconds
      }
    });
  }

  static createUsageSessionEndedEvent({ deviceId, policyVersion, targetType, target, durationSeconds, startTime, endTime }) {
    return this.createEvent({
      type: EventType.APP_SESSION_ENDED,
      deviceId,
      policyVersion,
      payload: {
        targetType,
        target,
        durationSeconds,
        startTime,
        endTime
      }
    });
  }
}

module.exports = {
  EventFactory,
  EventType
};
