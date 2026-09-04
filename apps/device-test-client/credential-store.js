/**
 * FocusGuard SecureCredentialStore Abstraction
 * 
 * Provides persistent storage for cryptographic device credentials.
 * Platform-Specific Implementations:
 * - macOS: Native Keychain Services (SecItemAdd/SecItemCopyMatching)
 * - Windows: Windows Credential Manager / DPAPI (CryptProtectData)
 * - Android: Android Keystore System (EncryptedSharedPreferences / MasterKey)
 * - Browser Extension: chrome.storage.local (Isolated from web DOM)
 * - Node.js Test Client: Local isolated JSON file (.focusguard-device-credentials.json)
 */

const fs = require('fs');
const path = require('path');

class SecureCredentialStore {
  constructor(storagePath = null) {
    this.storagePath = storagePath || path.join(__dirname, '.focusguard-device-credentials.json');
  }

  /**
   * Persists device credential metadata and keys.
   * @param {object} credentialData
   */
  async saveCredentials(credentialData) {
    try {
      const payload = JSON.stringify({
        ...credentialData,
        savedAt: new Date().toISOString()
      }, null, 2);
      fs.writeFileSync(this.storagePath, payload, { mode: 0o600 });
      return true;
    } catch (err) {
      console.error('[SecureCredentialStore] Failed to save credentials:', err);
      return false;
    }
  }

  /**
   * Loads saved device credential.
   * @returns {object|null}
   */
  async loadCredentials() {
    try {
      if (!fs.existsSync(this.storagePath)) {
        return null;
      }
      const data = fs.readFileSync(this.storagePath, 'utf8');
      return JSON.parse(data);
    } catch (err) {
      console.error('[SecureCredentialStore] Failed to load credentials:', err);
      return null;
    }
  }

  /**
   * Clears device credentials upon revocation.
   */
  async clearCredentials() {
    try {
      if (fs.existsSync(this.storagePath)) {
        fs.unlinkSync(this.storagePath);
      }
      return true;
    } catch (err) {
      console.error('[SecureCredentialStore] Failed to clear credentials:', err);
      return false;
    }
  }

  /**
   * Checks if valid credential exists.
   * @returns {boolean}
   */
  hasCredentials() {
    return fs.existsSync(this.storagePath);
  }
}

module.exports = SecureCredentialStore;
