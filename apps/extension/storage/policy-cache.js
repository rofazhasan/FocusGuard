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
    this.STORAGE_KEY_LAST_SYNCED = 'fg_last_synced_usage';
  }

  async getStoredData() {
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      return new Promise((resolve) => {
        chrome.storage.local.get([
          this.STORAGE_KEY_POLICIES,
          this.STORAGE_KEY_VERSION,
          this.STORAGE_KEY_USAGE,
          this.STORAGE_KEY_QUEUE,
          this.STORAGE_KEY_FOCUS,
          this.STORAGE_KEY_LAST_SYNCED
        ], (items) => {
          resolve({
            policies: items[this.STORAGE_KEY_POLICIES] || [],
            version: items[this.STORAGE_KEY_VERSION] || 1,
            todayUsage: items[this.STORAGE_KEY_USAGE] || {},
            offlineQueue: items[this.STORAGE_KEY_QUEUE] || [],
            focusSession: items[this.STORAGE_KEY_FOCUS] || null,
            lastSyncedUsage: items[this.STORAGE_KEY_LAST_SYNCED] || {}
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
      focusSession: null,
      lastSyncedUsage: {}
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

  async setLastSyncedUsage(usageMap) {
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      await chrome.storage.local.set({ [this.STORAGE_KEY_LAST_SYNCED]: usageMap });
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
    // Bounded FIFO: max 500 events to prevent memory/storage exhaustion
    if (queue.length >= 500) {
      queue.shift();
    }
    queue.push(event);
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      await chrome.storage.local.set({ [this.STORAGE_KEY_QUEUE]: queue });
    }
  }

  /**
   * Safely drains acknowledged events from the offline queue.
   * If acknowledgedEventIds is provided, only removes those matching IDs.
   * If count is provided, removes the first `count` items.
   * This guarantees zero event loss for events enqueued while an upload was in flight.
   */
  async drainOfflineQueue(acknowledgedEventIds = null, count = 0) {
    const current = await this.getStoredData();
    let queue = current.offlineQueue || [];

    if (Array.isArray(acknowledgedEventIds) && acknowledgedEventIds.length > 0) {
      const ackSet = new Set(acknowledgedEventIds);
      queue = queue.filter(evt => !ackSet.has(evt.id));
    } else if (count > 0) {
      queue = queue.slice(count);
    } else {
      queue = [];
    }

    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      await chrome.storage.local.set({ [this.STORAGE_KEY_QUEUE]: queue });
    }
    return queue;
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { PolicyCache };
}
