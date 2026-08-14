/**
 * FocusGuard Browser Extension — Session & Active-Time Tracker
 * 
 * Implements an active visibility time algorithm with idle detection,
 * window focus tracking, tab switching, and state machine transitions.
 */

const SessionState = {
  UNKNOWN: 'UNKNOWN',
  ACTIVE: 'ACTIVE',
  IDLE: 'IDLE',
  PAUSED: 'PAUSED',
  ENDED: 'ENDED'
};

class SessionTracker {
  /**
   * @param {Object} options
   * @param {number} [options.idleThresholdSeconds=60] Inactivity timeout before state becomes IDLE
   * @param {Function} [options.onUsageTick] Callback invoked when active duration updates
   * @param {Function} [options.onStateChange] Callback invoked on state transition
   */
  constructor(options = {}) {
    this.idleThresholdSeconds = options.idleThresholdSeconds || 60;
    this.onUsageTick = options.onUsageTick || (() => {});
    this.onStateChange = options.onStateChange || (() => {});

    this.currentDomain = null;
    this.currentTabId = null;
    this.currentWindowId = null;
    this.state = SessionState.UNKNOWN;

    this.sessionStartTime = null;
    this.lastActiveTime = null;
    this.accumulatedActiveSeconds = 0;
    this.isWindowFocused = true;
    this.isSystemIdle = false;

    this.tickInterval = null;
  }

  /**
   * Starts tracking active visibility time for a given domain and tab.
   * @param {string} domain - Hostname of active tab
   * @param {number} tabId
   * @param {number} windowId
   */
  startSession(domain, tabId, windowId) {
    const cleanDomain = typeof DomainMatcher !== 'undefined' ? DomainMatcher.normalizeDomain(domain) : domain.toLowerCase().replace(/^https?:\/\//, '').split('/')[0];
    
    // If already tracking this domain in active state, continue
    if (this.currentDomain === cleanDomain && this.state === SessionState.ACTIVE) {
      return;
    }

    // End previous session if domain changed
    if (this.currentDomain && this.currentDomain !== cleanDomain) {
      this.endSession();
    }

    const now = Date.now();
    this.currentDomain = cleanDomain;
    this.currentTabId = tabId;
    this.currentWindowId = windowId;
    this.sessionStartTime = now;
    this.lastActiveTime = now;
    this.accumulatedActiveSeconds = 0;

    this._transitionState(this.isWindowFocused && !this.isSystemIdle ? SessionState.ACTIVE : SessionState.PAUSED);
    this._startTicker();
  }

  /**
   * Handles tab activation or URL change.
   */
  onTabActivated(domain, tabId, windowId) {
    if (!domain) {
      this.pauseSession();
      return;
    }
    this.startSession(domain, tabId, windowId);
  }

  /**
   * Handles browser window focus change.
   */
  onWindowFocusChanged(isFocused) {
    this.isWindowFocused = isFocused;
    if (!isFocused) {
      if (this.state === SessionState.ACTIVE) {
        this.pauseSession();
      }
    } else {
      if (this.currentDomain && (this.state === SessionState.PAUSED || this.state === SessionState.IDLE)) {
        this.resumeSession();
      }
    }
  }

  /**
   * Handles system or browser idle state changes.
   * @param {'active'|'idle'|'locked'} idleState
   */
  onIdleStateChanged(idleState) {
    this.isSystemIdle = idleState !== 'active';
    if (this.isSystemIdle) {
      if (this.state === SessionState.ACTIVE) {
        this._transitionState(SessionState.IDLE);
      }
    } else {
      if (this.currentDomain && this.isWindowFocused && this.state === SessionState.IDLE) {
        this.resumeSession();
      }
    }
  }

  pauseSession() {
    if (this.state === SessionState.ACTIVE) {
      this._transitionState(SessionState.PAUSED);
    }
  }

  resumeSession() {
    if (this.currentDomain && !this.isSystemIdle && this.isWindowFocused) {
      this.lastActiveTime = Date.now();
      this._transitionState(SessionState.ACTIVE);
    }
  }

  endSession() {
    if (this.state === SessionState.ENDED || !this.currentDomain) {
      return null;
    }

    this._stopTicker();
    const duration = this.accumulatedActiveSeconds;
    const sessionSummary = {
      domain: this.currentDomain,
      durationSeconds: duration,
      startTime: this.sessionStartTime,
      endTime: Date.now()
    };

    this._transitionState(SessionState.ENDED);
    this.currentDomain = null;
    this.currentTabId = null;
    this.accumulatedActiveSeconds = 0;

    return sessionSummary;
  }

  _transitionState(newState) {
    if (this.state === newState) return;
    const oldState = this.state;
    this.state = newState;
    this.onStateChange(newState, oldState, this.currentDomain);
  }

  _startTicker() {
    this._stopTicker();
    this.tickInterval = setInterval(() => {
      if (this.state === SessionState.ACTIVE && this.currentDomain) {
        const now = Date.now();
        const deltaSeconds = Math.max(1, Math.round((now - this.lastActiveTime) / 1000));
        this.lastActiveTime = now;
        this.accumulatedActiveSeconds += deltaSeconds;

        this.onUsageTick({
          domain: this.currentDomain,
          totalDurationSeconds: this.accumulatedActiveSeconds,
          deltaSeconds: deltaSeconds,
          state: this.state
        });
      }
    }, 1000);
  }

  _stopTicker() {
    if (this.tickInterval) {
      clearInterval(this.tickInterval);
      this.tickInterval = null;
    }
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { SessionTracker, SessionState };
}
