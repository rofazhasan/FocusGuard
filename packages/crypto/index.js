/**
 * FocusGuard Crypto Package
 * Cryptographic device identity generation, challenge-response verification,
 * HMAC token signing, and replay protection.
 */

const crypto = require('crypto');

class CryptoEngine {
  /**
   * Generates a random cryptographic identifier (e.g. deviceId, pairingCode, sessionId).
   * @param {number} bytes 
   * @returns {string} hex string
   */
  static generateId(bytes = 16) {
    return crypto.randomBytes(bytes).toString('hex');
  }

  /**
   * Generates a high-entropy secret key for device credentials.
   * @returns {string} 32-byte hex secret
   */
  static generateDeviceKey() {
    return crypto.randomBytes(32).toString('hex');
  }

  /**
   * Generates a human-friendly 6-character alphanumeric pairing code.
   * Excludes ambiguous characters (0, O, 1, I).
   * @returns {string}
   */
  static generatePairingCode() {
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    let code = '';
    const bytes = crypto.randomBytes(6);
    for (let i = 0; i < 6; i++) {
      code += chars[bytes[i] % chars.length];
    }
    return code;
  }

  /**
   * Computes HMAC-SHA256 signature for message integrity and authentication.
   * @param {string} payload 
   * @param {string} secretKey 
   * @returns {string} hex signature
   */
  static sign(payload, secretKey) {
    return crypto
      .createHmac('sha256', secretKey)
      .update(typeof payload === 'string' ? payload : JSON.stringify(payload))
      .digest('hex');
  }

  /**
   * Verifies an HMAC-SHA256 signature in constant time against timing attacks.
   * @param {string} payload 
   * @param {string} signature 
   * @param {string} secretKey 
   * @returns {boolean}
   */
  static verifySignature(payload, signature, secretKey) {
    if (!signature || !secretKey) return false;
    const expected = this.sign(payload, secretKey);
    try {
      return crypto.timingSafeEqual(Buffer.from(signature, 'hex'), Buffer.from(expected, 'hex'));
    } catch (e) {
      return false;
    }
  }

  /**
   * Validates command freshness and replay attack prevention (within tolerance window).
   * @param {number} timestampMs 
   * @param {number} maxAgeSeconds 
   * @returns {boolean}
   */
  static isTimestampValid(timestampMs, maxAgeSeconds = 300) {
    const now = Date.now();
    const diff = Math.abs(now - timestampMs);
    return diff <= maxAgeSeconds * 1000;
  }
}

module.exports = CryptoEngine;
