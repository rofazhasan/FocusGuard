/**
 * FocusGuard Browser Extension — Background Service Worker
 * 
 * Orchestrates domain matching, local policy enforcement, active-visibility usage tracking,
 * idle detection, WebSocket synchronization, and block page redirection.
 */

// Import Core Modules
importScripts(
  '../core/domain-matcher.js',
  '../core/session-tracker.js',
  '../core/dnr-compiler.js',
  '../storage/policy-cache.js',
  '../policy/policy-engine.js'
);

const API_BASE = 'http://localhost:8080/api/v1';
const WS_URL = 'ws://localhost:8080/ws';

const policyCache = new PolicyCache();
const policyEngine = new ExtensionPolicyEngine(DomainMatcher);
let wsConnection = null;
let currentPolicyVersion = 1;

// Initialize Session Tracker with 60s idle threshold
const sessionTracker = new SessionTracker({
  idleThresholdSeconds: 60,
  onUsageTick: async (tick) => {
    // Increment today's usage in policy engine
    policyEngine.updateUsage(tick.domain, tick.deltaSeconds);
    await policyCache.setTodayUsage(policyEngine.todayUsage);

    // Evaluate if this usage now triggers a block
    const evalResult = policyEngine.evaluate(tick.domain);
    if (evalResult.action === 'BLOCK' && sessionTracker.currentTabId) {
      redirectToBlockPage(sessionTracker.currentTabId, tick.domain, evalResult);
    }
  },
  onStateChange: (newState, oldState, domain) => {
    console.log(`[FocusGuard Tracker] State transition: ${oldState} -> ${newState} (${domain})`);
  }
});

/**
 * Redirects tab to the FocusGuard block page.
 */
function redirectToBlockPage(tabId, urlOrDomain, evalResult) {
  const blockUrl = chrome.runtime.getURL(
    `pages/block.html?target=${encodeURIComponent(DomainMatcher.normalizeDomain(urlOrDomain))}` +
    `&reason=${encodeURIComponent(evalResult.reason || 'Attention Budget Reached')}` +
    `&policy=${encodeURIComponent(evalResult.policyName || 'FocusGuard Policy')}` +
    `&used=${encodeURIComponent(evalResult.usedMinutes || 30)}` +
    `&limit=${encodeURIComponent(evalResult.limitMinutes || 30)}` +
    `&reset=${encodeURIComponent(evalResult.nextReset || '12:00 AM')}`
  );

  chrome.tabs.update(tabId, { url: blockUrl });
}

/**
 * Initializes policies and connects WebSocket.
 */
async function initializeExtension() {
  console.log('[FocusGuard Extension] Initializing service worker...');

  // 1. Load cached policies and state
  const cached = await policyCache.getStoredData();
  currentPolicyVersion = cached.version || 1;
  policyEngine.setPolicies(cached.policies);
  policyEngine.setTodayUsage(cached.todayUsage);
  policyEngine.setFocusSession(cached.focusSession);

  // 2. Fetch fresh policies from backend
  await fetchPoliciesFromServer();

  // 3. Connect real-time WebSocket hub
  connectWebSocket();

  // 4. Setup periodic usage sync alarm (every 1 minute)
  if (chrome.alarms) {
    chrome.alarms.create('fg_usage_sync', { periodInMinutes: 1 });
  }
}

/**
 * Fetches versioned policies from server.
 */
async function fetchPoliciesFromServer() {
  try {
    const resp = await fetch(`${API_BASE}/policies`, { credentials: 'omit' });
    if (resp.ok) {
      const data = await resp.json();
      const serverVersion = data.version || (data.length > 0 ? 2 : 1);
      if (serverVersion >= currentPolicyVersion) {
        currentPolicyVersion = serverVersion;
        const policies = data.policies || data;
        policyEngine.setPolicies(policies);
        await policyCache.updatePolicies(policies, serverVersion);

        // Compile and sync native browser DeclarativeNetRequest dynamic rules
        if (typeof DNRPolicyCompiler !== 'undefined') {
          const dynamicRules = DNRPolicyCompiler.compileDynamicRules(policies, policyEngine.todayUsage);
          await DNRPolicyCompiler.syncWithBrowser(dynamicRules);
        }

        console.log(`[FocusGuard Extension] Applied synchronized policy v${serverVersion} with native DNR rules.`);
      }
    }
  } catch (err) {
    console.warn('[FocusGuard Extension] Backend unreachable; operating in 100% offline cache mode.', err);
  }
}

/**
 * Real-time WebSocket connection for instant remote focus and limits.
 */
function connectWebSocket() {
  if (wsConnection) {
    try { wsConnection.close(); } catch (e) {}
  }

  try {
    wsConnection = new WebSocket(WS_URL);

    wsConnection.onopen = () => {
      console.log('[FocusGuard Extension] Real-time WebSocket connected');
      wsConnection.send(JSON.stringify({
        type: 'REGISTER_DEVICE',
        deviceId: 'extension-browser-node',
        platform: 'WEB_EXTENSION'
      }));
    };

    wsConnection.onmessage = async (msg) => {
      try {
        const payload = JSON.parse(msg.data);
        console.log('[FocusGuard Extension] WS event received:', payload);

        if (payload.type === 'POLICY_UPDATED') {
          await fetchPoliciesFromServer();
        } else if (payload.type === 'FOCUS_SESSION_STARTED') {
          policyEngine.setFocusSession({
            isActive: true,
            name: payload.name || 'Remote Focus Session',
            durationMinutes: payload.durationMinutes || 45,
            allowedDomains: payload.allowedDomains || ['github.com', 'stackoverflow.com']
          });
          await policyCache.setFocusSession(policyEngine.focusSession);
          // Check currently active tab
          if (sessionTracker.currentTabId && sessionTracker.currentDomain) {
            const evalResult = policyEngine.evaluate(sessionTracker.currentDomain);
            if (evalResult.action === 'BLOCK') {
              redirectToBlockPage(sessionTracker.currentTabId, sessionTracker.currentDomain, evalResult);
            }
          }
        } else if (payload.type === 'FOCUS_SESSION_ENDED') {
          policyEngine.setFocusSession(null);
          await policyCache.setFocusSession(null);
        } else if (payload.type === 'LIMIT_REACHED') {
          policyEngine.updateUsage(payload.targetValue, payload.limitSeconds || 1800);
          if (sessionTracker.currentTabId && sessionTracker.currentDomain && 
              DomainMatcher.isDomainMatch(sessionTracker.currentDomain, payload.targetValue)) {
            const evalResult = policyEngine.evaluate(sessionTracker.currentDomain);
            redirectToBlockPage(sessionTracker.currentTabId, sessionTracker.currentDomain, evalResult);
          }
        }
      } catch (e) {
        console.error('[FocusGuard Extension] Error handling WS message', e);
      }
    };

    wsConnection.onclose = () => {
      console.log('[FocusGuard Extension] WS closed, reconnecting in 5s...');
      setTimeout(connectWebSocket, 5000);
    };

    wsConnection.onerror = (err) => {
      console.warn('[FocusGuard Extension] WS error:', err);
    };
  } catch (err) {
    console.warn('[FocusGuard Extension] WS initialization failed:', err);
  }
}

// ---------------- Navigation & Enforcement Interceptors ----------------

chrome.webNavigation.onBeforeNavigate.addListener((details) => {
  if (details.frameId !== 0) return; // Main frame only
  const url = details.url;
  if (url.startsWith('chrome://') || url.startsWith('chrome-extension://') || url.startsWith('about:')) return;

  const evalResult = policyEngine.evaluate(url);
  if (evalResult.action === 'BLOCK') {
    redirectToBlockPage(details.tabId, url, evalResult);
  }
});

// ---------------- Active-Time Visibility & Idle Listeners ----------------

chrome.tabs.onActivated.addListener(async (activeInfo) => {
  try {
    const tab = await chrome.tabs.get(activeInfo.tabId);
    if (tab && tab.url && !tab.url.startsWith('chrome-extension://')) {
      sessionTracker.onTabActivated(tab.url, tab.id, tab.windowId);
      const evalResult = policyEngine.evaluate(tab.url);
      if (evalResult.action === 'BLOCK') {
        redirectToBlockPage(tab.id, tab.url, evalResult);
      }
    } else {
      sessionTracker.pauseSession();
    }
  } catch (err) {
    sessionTracker.pauseSession();
  }
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.url && tab.active && !changeInfo.url.startsWith('chrome-extension://')) {
    sessionTracker.onTabActivated(changeInfo.url, tabId, tab.windowId);
    const evalResult = policyEngine.evaluate(changeInfo.url);
    if (evalResult.action === 'BLOCK') {
      redirectToBlockPage(tabId, changeInfo.url, evalResult);
    }
  }
});

chrome.windows.onFocusChanged.addListener((windowId) => {
  sessionTracker.onWindowFocusChanged(windowId !== chrome.windows.WINDOW_ID_NONE);
});

if (chrome.idle) {
  chrome.idle.setDetectionInterval(60);
  chrome.idle.onStateChanged.addListener((newState) => {
    sessionTracker.onIdleStateChanged(newState);
  });
}

// Periodic Alarm for Usage Synchronization
if (chrome.alarms) {
  chrome.alarms.onAlarm.addListener(async (alarm) => {
    if (alarm.name === 'fg_usage_sync') {
      try {
        const cached = await policyCache.getStoredData();
        const usageDeltas = Object.entries(cached.todayUsage).map(([target, sec]) => ({
          targetValue: target,
          durationSeconds: sec,
          date: new Date().toISOString().split('T')[0]
        }));

        if (usageDeltas.length > 0) {
          await fetch(`${API_BASE}/usage/sync`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              deviceId: '00000000-0000-0000-0000-000000000002',
              usageDeltas: usageDeltas
            })
          });
        }
      } catch (err) {
        console.warn('[FocusGuard Extension] Periodic sync skipped (offline mode).');
      }
    }
  });
}

// Lifecycle Init
initializeExtension();
