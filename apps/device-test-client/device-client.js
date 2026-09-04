/**
 * FocusGuard Simulated Device Test Client
 * Implements the full Phase 2 client lifecycle: key generation, pairing submission,
 * status polling, persistent credential storage, automatic reconnection, heartbeat,
 * policy synchronization, event batch ingestion, and revocation handling.
 */

const crypto = require('crypto');
const SecureCredentialStore = require('./credential-store.js');

class FocusGuardDeviceClient {
  constructor(options = {}) {
    this.apiBase = options.apiBase || 'http://localhost:8080/api/v1';
    this.deviceName = options.deviceName || 'Pixel 8 Pro (Simulated)';
    this.platform = options.platform || 'ANDROID';
    this.clientType = options.clientType || 'ANDROID_APP';
    this.appVersion = options.appVersion || '2.0.0';
    this.store = new SecureCredentialStore(options.credentialPath);

    this.state = 'UNREGISTERED'; // UNREGISTERED, PAIRING, PENDING_APPROVAL, ACTIVE, OFFLINE, REVOKED
    this.keyPair = null;
    this.deviceId = null;
    this.deviceToken = null;
    this.policyVersion = 1;
    this.policies = [];
  }

  /**
   * Generates a new cryptographic asymmetric keypair on the client.
   * Private key remains strictly device-local.
   */
  generateIdentity() {
    const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519', {
      publicKeyEncoding: { type: 'spki', format: 'pem' },
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' }
    });

    this.keyPair = { publicKey, privateKey };
    return this.keyPair;
  }

  /**
   * Initializes the client: loads saved credentials if available, otherwise stays UNREGISTERED.
   */
  async initialize() {
    const saved = await this.store.loadCredentials();
    if (saved && saved.deviceToken && saved.deviceId) {
      this.deviceId = saved.deviceId;
      this.deviceToken = saved.deviceToken;
      this.deviceName = saved.deviceName || this.deviceName;
      this.platform = saved.platform || this.platform;
      this.keyPair = saved.keyPair || null;
      this.state = 'ACTIVE';
      return { paired: true, deviceId: this.deviceId };
    }
    this.state = 'UNREGISTERED';
    return { paired: false };
  }

  /**
   * Submits an enrollment request to a pairing session.
   * @param {string} sessionIdOrCode
   */
  async startPairing(sessionIdOrCode) {
    if (!this.keyPair) {
      this.generateIdentity();
    }

    this.state = 'PAIRING';

    const isUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(sessionIdOrCode);
    const url = isUUID
      ? `${this.apiBase}/pairing/sessions/${sessionIdOrCode}/request`
      : `${this.apiBase}/pairing/request`;

    const body = {
      deviceName: this.deviceName,
      platform: this.platform,
      clientType: this.clientType,
      appVersion: this.appVersion,
      publicKey: this.keyPair.publicKey,
      keyAlgorithm: 'Ed25519'
    };

    if (!isUUID) {
      body.pairingCode = sessionIdOrCode;
    }

    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(`Pairing request failed (${res.status}): ${err.error?.message || res.statusText}`);
    }

    const data = await res.json();
    this.state = 'PENDING_APPROVAL';
    return data;
  }

  /**
   * Polls session status until approved, rejected, or expired.
   * @param {string} sessionId
   * @param {number} maxAttempts
   * @param {number} intervalMs
   */
  async pollForApproval(sessionId, maxAttempts = 30, intervalMs = 1000) {
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      const res = await fetch(`${this.apiBase}/pairing/sessions/${sessionId}/status`);
      if (res.ok) {
        const data = await res.json();
        if (data.status === 'APPROVED') {
          this.deviceId = data.deviceId;
          this.deviceToken = data.deviceToken;
          this.state = 'ACTIVE';

          // Securely persist credentials
          await this.store.saveCredentials({
            deviceId: this.deviceId,
            deviceToken: this.deviceToken,
            deviceName: this.deviceName,
            platform: this.platform,
            clientType: this.clientType,
            appVersion: this.appVersion,
            keyPair: this.keyPair,
            enrolledAt: new Date().toISOString()
          });

          return { success: true, deviceId: this.deviceId, deviceToken: this.deviceToken };
        } else if (data.status === 'REJECTED') {
          this.state = 'REVOKED';
          throw new Error('Pairing request was rejected by account owner');
        } else if (data.status === 'EXPIRED' || data.status === 'CANCELLED') {
          this.state = 'UNREGISTERED';
          throw new Error(`Pairing session ${data.status.toLowerCase()}`);
        }
      }

      await new Promise(r => setTimeout(r, intervalMs));
    }

    throw new Error('Pairing poll timed out waiting for approval');
  }

  /**
   * Sends heartbeat with device status and health metadata.
   */
  async sendHeartbeat() {
    if (!this.deviceToken || !this.deviceId) {
      throw new Error('Device not paired or missing credentials');
    }

    const res = await fetch(`${this.apiBase}/devices/${this.deviceId}/heartbeat`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.deviceToken}`
      },
      body: JSON.stringify({
        appVersion: this.appVersion,
        policyVersion: this.policyVersion,
        protectionState: 'PROTECTED',
        timestamp: new Date().toISOString(),
        healthMetadata: { batteryLevel: 95, syncOk: true }
      })
    });

    if (res.status === 403 || res.status === 401) {
      const err = await res.json().catch(() => ({}));
      if (err.error?.code === 'DEVICE_REVOKED' || res.status === 403) {
        this.state = 'REVOKED';
        await this.store.clearCredentials();
        throw new Error('DEVICE_REVOKED: This device has been revoked by account owner');
      }
    }

    if (!res.ok) {
      throw new Error(`Heartbeat failed (${res.status})`);
    }

    return await res.json();
  }

  /**
   * Synchronizes versioned policies from server.
   */
  async syncPolicies() {
    if (!this.deviceToken) {
      throw new Error('Device not paired or missing credentials');
    }

    const res = await fetch(`${this.apiBase}/device/policies/sync`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${this.deviceToken}`
      }
    });

    if (res.status === 403 || res.status === 401) {
      const err = await res.json().catch(() => ({}));
      if (err.error?.code === 'DEVICE_REVOKED' || res.status === 403) {
        this.state = 'REVOKED';
        await this.store.clearCredentials();
        throw new Error('DEVICE_REVOKED: Device was revoked');
      }
    }

    if (!res.ok) {
      throw new Error(`Policy sync failed (${res.status})`);
    }

    const data = await res.json();
    this.policyVersion = data.policyVersion || this.policyVersion;
    this.policies = data.policies || [];
    return data;
  }

  /**
   * Ingests a batch of telemetry / enforcement events to cloud backend.
   * @param {Array<object>} events
   */
  async sendEvents(events) {
    if (!this.deviceToken) {
      throw new Error('Device not paired or missing credentials');
    }

    const res = await fetch(`${this.apiBase}/events/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.deviceToken}`
      },
      body: JSON.stringify({ events })
    });

    if (!res.ok) {
      throw new Error(`Event batch upload failed (${res.status})`);
    }

    return await res.json();
  }
}

module.exports = FocusGuardDeviceClient;
