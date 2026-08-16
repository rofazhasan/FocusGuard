/**
 * FocusGuard Protocol Package
 * Realtime WebSocket envelope specifications, REST endpoint constants, and message schemas.
 */

const MessageType = {
  // Client -> Server
  AUTH: 'AUTH',
  HEARTBEAT: 'HEARTBEAT',
  REPORT_USAGE: 'REPORT_USAGE',
  REPORT_EVENT: 'REPORT_EVENT',
  POLICY_PULL: 'POLICY_PULL',

  // Server -> Client
  AUTH_SUCCESS: 'AUTH_SUCCESS',
  AUTH_ERROR: 'AUTH_ERROR',
  POLICY_PUSH: 'POLICY_PUSH',
  COMMAND: 'COMMAND',
  HEARTBEAT_ACK: 'HEARTBEAT_ACK'
};

class ProtocolEnvelope {
  /**
   * Constructs a standard WebSocket envelope.
   * @param {string} type 
   * @param {object} payload 
   * @param {string} [correlationId]
   * @returns {string} JSON string
   */
  static pack(type, payload = {}, correlationId = null) {
    return JSON.stringify({
      type,
      correlationId: correlationId || `cor_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
      timestamp: Date.now(),
      payload
    });
  }

  /**
   * Parses and validates an incoming envelope.
   * @param {string|Buffer} raw 
   * @returns {object}
   */
  static unpack(raw) {
    try {
      const data = typeof raw === 'string' ? JSON.parse(raw) : JSON.parse(raw.toString('utf8'));
      if (!data.type) {
        throw new Error('Protocol envelope missing "type" field');
      }
      return data;
    } catch (e) {
      throw new Error(`Invalid protocol envelope: ${e.message}`);
    }
  }
}

module.exports = {
  MessageType,
  ProtocolEnvelope
};
