/**
 * FocusGuard Validation Package
 * Input validation schemas and boundary assertions for security and stability.
 */

const { TargetType, ActionType, Platform } = require('../shared-types/index.js');

class ValidationEngine {
  /**
   * Validates policy creation and update payloads.
   * @param {object} policy 
   * @returns {{ valid: boolean, errors: string[] }}
   */
  static validatePolicy(policy) {
    const errors = [];
    if (!policy || typeof policy !== 'object') {
      return { valid: false, errors: ['Policy must be an object'] };
    }

    if (!policy.id || typeof policy.id !== 'string') {
      errors.push('Policy "id" is required and must be a string');
    }

    if (!TargetType[policy.targetType]) {
      errors.push(`Invalid targetType: ${policy.targetType}. Must be one of: ${Object.keys(TargetType).join(', ')}`);
    }

    if (!policy.target || typeof policy.target !== 'string' || policy.target.trim() === '') {
      errors.push('Policy "target" is required and cannot be empty');
    }

    if (!ActionType[policy.action]) {
      errors.push(`Invalid action: ${policy.action}. Must be one of: ${Object.keys(ActionType).join(', ')}`);
    }

    if (policy.action === ActionType.TIME_LIMIT || policy.action === ActionType.APP_LIMIT) {
      if (typeof policy.limit !== 'number' || policy.limit <= 0) {
        errors.push('Action TIME_LIMIT/APP_LIMIT requires "limit" in seconds greater than 0');
      }
    }

    if (policy.version !== undefined && (typeof policy.version !== 'number' || policy.version < 1)) {
      errors.push('Policy "version" must be a positive integer');
    }

    return {
      valid: errors.length === 0,
      errors
    };
  }

  /**
   * Validates device enrollment payloads.
   * @param {object} enrollment 
   * @returns {{ valid: boolean, errors: string[] }}
   */
  static validateEnrollment(enrollment) {
    const errors = [];
    if (!enrollment || typeof enrollment !== 'object') {
      return { valid: false, errors: ['Enrollment must be an object'] };
    }

    if (!Platform[enrollment.platform]) {
      errors.push(`Invalid platform: ${enrollment.platform}`);
    }

    if (!enrollment.pairingCode || typeof enrollment.pairingCode !== 'string' || enrollment.pairingCode.length !== 6) {
      errors.push('Valid 6-character "pairingCode" is required');
    }

    return {
      valid: errors.length === 0,
      errors
    };
  }
}

module.exports = ValidationEngine;
