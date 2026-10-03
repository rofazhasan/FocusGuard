/**
 * FocusGuard Browser Extension — Active Content Script Tracker
 * 
 * Injected into all web pages to:
 * 1. Maintain an active keep-alive port with the MV3 background service worker.
 * 2. Track real page visibility (document.visibilityState, document.hasFocus).
 * 3. Intercept Single Page Application (SPA) client-side routing (YouTube, Reddit, Twitter/X).
 * 4. Instantly redirect tab upon receiving an authoritative BLOCK enforcement command.
 */

(function() {
  'use strict';

  // Prevent double-injection
  if (window.__focusguard_tracker_installed) return;
  window.__focusguard_tracker_installed = true;

  // Skip browser internal pages
  const href = window.location.href;
  if (href.startsWith('chrome-extension://') || href.startsWith('about:') || href.startsWith('chrome://')) {
    return;
  }

  let port = null;
  let heartbeatTimer = null;
  let isTabVisible = document.visibilityState === 'visible' && !document.hidden;
  let lastUserActivity = Date.now();

  function recordActivity() {
    lastUserActivity = Date.now();
  }

  window.addEventListener('mousemove', recordActivity, { passive: true });
  window.addEventListener('keydown', recordActivity, { passive: true });
  window.addEventListener('scroll', recordActivity, { passive: true });
  window.addEventListener('click', recordActivity, { passive: true });

  function connectPort() {
    try {
      if (port) {
        try { port.disconnect(); } catch (e) {}
        port = null;
      }

      port = chrome.runtime.connect({ name: 'focusguard-tracker' });
      
      port.onMessage.addListener((msg) => {
        if (msg && msg.type === 'ENFORCE_BLOCK' && msg.blockUrl) {
          // Instantly replace window location with the block screen
          window.location.replace(msg.blockUrl);
        }
      });

      port.onDisconnect.addListener(() => {
        port = null;
        if (isTabVisible) {
          // Reconnect after brief backoff
          setTimeout(connectPort, 1000);
        }
      });

      // Announce initial page load
      sendActiveTick();
    } catch (err) {
      // Runtime context might be invalidated during extension reload
    }
  }

  function sendActiveTick() {
    if (!port) {
      connectPort();
      return;
    }

    const now = Date.now();
    const isUserActive = (now - lastUserActivity) < 60000; // Active within last 60 seconds

    if (isTabVisible && isUserActive) {
      try {
        port.postMessage({
          type: 'PAGE_ACTIVE_TICK',
          url: window.location.href,
          hostname: window.location.hostname,
          title: document.title,
          timestamp: now
        });
      } catch (e) {
        port = null;
      }
    }
  }

  function startHeartbeat() {
    if (heartbeatTimer) clearInterval(heartbeatTimer);
    heartbeatTimer = setInterval(() => {
      if (document.visibilityState === 'visible') {
        isTabVisible = true;
        sendActiveTick();
      } else {
        isTabVisible = false;
      }
    }, 1000);
  }

  // Handle visibility transitions
  document.addEventListener('visibilitychange', () => {
    isTabVisible = document.visibilityState === 'visible';
    if (isTabVisible) {
      recordActivity();
      if (!port) connectPort();
      sendActiveTick();
    }
  });

  window.addEventListener('focus', () => {
    isTabVisible = true;
    recordActivity();
    if (!port) connectPort();
    sendActiveTick();
  });

  window.addEventListener('blur', () => {
    isTabVisible = false;
  });

  // Intercept Single Page App (SPA) navigations (e.g. YouTube video clicks, Twitter tabs)
  function handleUrlChange() {
    recordActivity();
    if (port) {
      try {
        port.postMessage({
          type: 'SPA_NAVIGATION',
          url: window.location.href,
          hostname: window.location.hostname
        });
      } catch (e) {
        connectPort();
      }
    }
  }

  window.addEventListener('popstate', handleUrlChange);
  window.addEventListener('hashchange', handleUrlChange);

  const originalPushState = history.pushState;
  if (originalPushState) {
    history.pushState = function() {
      const result = originalPushState.apply(this, arguments);
      handleUrlChange();
      return result;
    };
  }

  const originalReplaceState = history.replaceState;
  if (originalReplaceState) {
    history.replaceState = function() {
      const result = originalReplaceState.apply(this, arguments);
      handleUrlChange();
      return result;
    };
  }

  // Initial startup
  connectPort();
  startHeartbeat();
})();
