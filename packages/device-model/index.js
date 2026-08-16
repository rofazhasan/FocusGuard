/**
 * FocusGuard Device Model Package
 * Cryptographic device identity, pairing state machine, and protection score calculator.
 */

const { PairingState, ProtectionState, Platform } = require('../shared-types/index.js');
const CryptoEngine = require('../crypto/index.js');

class DeviceModel {
  /**
   * Generates a new cryptographic device record.
   * NEVER uses MAC address, IMEI, or hardware IDs as primary identity.
   */
  static createDeviceRecord({ platform, platformVersion = '1.0', appVersion = '1.0.0', deviceName }) {
    if (!Platform[platform]) {
      throw new Error(`Invalid Platform: ${platform}`);
    }

    const deviceId = `dev_${CryptoEngine.generateId(12)}`;
    const deviceKey = CryptoEngine.generateDeviceKey();
    const now = Date.now();

    return {
      deviceId,
      deviceKey,
      platform,
      platformVersion,
      appVersion,
      deviceName: deviceName || `FocusGuard ${platform}`,
      pairingState: PairingState.UNPAIRED,
      protectionState: ProtectionState.PROTECTED,
      policyVersion: 1,
      createdAt: now,
      lastSeen: now
    };
  }

  /**
   * Validates state transitions in the Pairing State Machine.
   * @param {string} currentState 
   * @param {string} nextState 
   * @returns {boolean}
   */
  static isValidStateTransition(currentState, nextState) {
    const validTransitions = {
      [PairingState.UNPAIRED]: [PairingState.PAIRING],
      [PairingState.PAIRING]: [PairingState.PENDING_APPROVAL, PairingState.UNPAIRED],
      [PairingState.PENDING_APPROVAL]: [PairingState.PAIRED, PairingState.UNTRUSTED, PairingState.UNPAIRED],
      [PairingState.PAIRED]: [PairingState.ACTIVE, PairingState.OFFLINE, PairingState.REVOKED, PairingState.BLOCKED],
      [PairingState.ACTIVE]: [PairingState.OFFLINE, PairingState.REVOKED, PairingState.BLOCKED],
      [PairingState.OFFLINE]: [PairingState.ACTIVE, PairingState.REVOKED, PairingState.BLOCKED],
      [PairingState.REVOKED]: [PairingState.UNPAIRED], // Must re-enroll from scratch
      [PairingState.BLOCKED]: [PairingState.REVOKED, PairingState.UNPAIRED],
      [PairingState.UNTRUSTED]: [PairingState.UNPAIRED]
    };

    return (validTransitions[currentState] || []).includes(nextState);
  }

  /**
   * Calculates the exact Protection Score percentage based on operational subsystems.
   * Never reports 100% if enforcement is actually unavailable or degraded.
   * @param {object} components
   * @param {boolean} components.policyCurrent
   * @param {boolean} components.usageDetection
   * @param {boolean} components.browserProtection
   * @param {boolean} components.networkProtection
   * @param {boolean} components.syncActive
   * @returns {{ score: number, status: string, breakdown: object }}
   */
  static calculateProtectionScore({
    policyCurrent = true,
    usageDetection = true,
    browserProtection = true,
    networkProtection = true,
    syncActive = true
  }) {
    let score = 0;
    if (policyCurrent) score += 20;
    if (usageDetection) score += 25;
    if (browserProtection) score += 25;
    if (networkProtection) score += 20;
    if (syncActive) score += 10;

    let status = ProtectionState.PROTECTED;
    if (score < 50) {
      status = ProtectionState.DEGRADED;
    } else if (score < 100) {
      status = ProtectionState.DEGRADED;
    }

    return {
      score,
      status,
      breakdown: {
        policyCurrent,
        usageDetection,
        browserProtection,
        networkProtection,
        syncActive
      }
    };
  }
}

module.exports = DeviceModel;
