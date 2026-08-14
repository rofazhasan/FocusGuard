/**
 * FocusGuard Browser Extension — Policy Cache & Offline Storage
 * 
 * Manages monotonic versioned policy storage, offline event queues,
 * and persistent local caching.
 */

class PolicyCache {
  constructor() {
    this.STORAGE_KEY_POLICIES = 'fg_policies';
    this.STORAGE_KEY_VERSION = 'fg_policy_version';
    this.STORAGE_KEY_USAGE = 'fg_today_usage';
    this.STORAGE_KEY_QUEUE = 'fg_offline_queue';
    this.STORAGE_KEY_FOCUS = 'fg_focus_session';
  }

  async getStoredData() {
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      return new Promise((resolve) => {
        chrome.storage.local.get([
          this.STORAGE_KEY_POLICIES,
          this.STORAGE_KEY_VERSION,
          this.STORAGE_KEY_USAGE,
          this.STORAGE_KEY_QUEUE,
          this.STORAGE_KEY_FOCUS
        ], (items) => {
          resolve({
            policies: items[this.STORAGE_KEY_POLICIES] || [],
            version: items[this.STORAGE_KEY_VERSION] || 1,
            todayUsage: items[this.STORAGE_KEY_USAGE] || {},
            offlineQueue: items[this.STORAGE_KEY_QUEUE] || [],
            focusSession: items[this.STORAGE_KEY_FOCUS] || null
          });
        });
      });
    }

    // Node / Memory Fallback
    return {
      policies: [],
      version: 1,
      todayUsage: {},
      offlineQueue: [],
      focusSession: null
    };
  }

  /**
   * Saves updated policies if incoming version >= cached version (monotonic guarantee).
   */
  async updatePolicies(newPolicies, newVersion) {
    const current = await this.getStoredData();
    if (newVersion < current.version) {
      console.warn(`[FocusGuard] Rejected stale policy version v${newVersion} (current: v${current.version})`);
      return false;
    }

    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      await chrome.storage.local.set({
        [this.STORAGE_KEY_POLICIES]: newPolicies,
        [this.STORAGE_KEY_VERSION]: newVersion
      });
    }
    return true;
  }

  async setTodayUsage(usageMap) {
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      await chrome.storage.local.set({ [this.STORAGE_KEY_USAGE]: usageMap });
    }
  }

  async setFocusSession(session) {
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      await chrome.storage.local.set({ [this.STORAGE_KEY_FOCUS]: session });
    }
  }

  async enqueueOfflineEvent(event) {
    const current = await this.getStoredData();
    const queue = current.offlineQueue || [];
    queue.push(event);
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      await chrome.storage.local.set({ [this.STORAGE_KEY_QUEUE]: queue });
    }
  }

  async drainOfflineQueue() {
    const current = await this.getStoredData();
    const queue = current.offlineQueue || [];
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      await chrome.storage.local.set({ [this.STORAGE_KEY_QUEUE]: [] });
    }
    return queue;
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { PolicyCache };
}
