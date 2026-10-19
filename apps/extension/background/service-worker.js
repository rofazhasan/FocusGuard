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
let authToken = null;
let cachedDeviceId = null;
let currentNetworkState = 'OFFLINE'; // ONLINE | DEGRADED | OFFLINE | RECONNECTING | SYNCING
let reconnectAttempts = 0;
let reconnectTimeoutId = null;

async function setNetworkState(newState) {
  if (currentNetworkState === newState) return;
  currentNetworkState = newState;
  if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
    await chrome.storage.local.set({ fg_network_state: newState });
  }
}

/**
 * Gets or dynamically generates a unique hardware/browser device identity.
 */
async function getOrCreateDeviceId() {
  if (cachedDeviceId) return cachedDeviceId;

  if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
    const data = await chrome.storage.local.get(['focusguard_device_id', 'focusguard_device_name', 'fg_pairing_status']);
    if (data && data.focusguard_device_id) {
      cachedDeviceId = data.focusguard_device_id;
      return cachedDeviceId;
    }

    const newId = (typeof crypto !== 'undefined' && crypto.randomUUID) ? crypto.randomUUID() : ('ext_' + Date.now() + '_' + Math.random().toString(36).substring(2, 9));
    const devName = 'Browser Extension (' + (typeof navigator !== 'undefined' && navigator.userAgent.includes('Firefox') ? 'Firefox' : 'Chrome') + ')';
    await chrome.storage.local.set({
      focusguard_device_id: newId,
      focusguard_device_name: devName,
      fg_pairing_status: data.fg_pairing_status || 'UNPAIRED'
    });
    cachedDeviceId = newId;
    return cachedDeviceId;
  }

  cachedDeviceId = '00000000-0000-0000-0000-000000000002';
  return cachedDeviceId;
}

/**
 * Retrieves cached JWT token from local storage, or attempts session authentication.
 */
async function getOrFetchAuthToken() {
  if (authToken) return authToken;

  try {
    if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
      const data = await chrome.storage.local.get(['focusguard_token', 'focusguard_device_token']);
      if (data && (data.focusguard_token || data.focusguard_device_token)) {
        authToken = data.focusguard_token || data.focusguard_device_token;
        return authToken;
      }
    }

    // Default primary demo user for frictionless developer zero-config
    const res = await fetch(`${API_BASE}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'demo@focusguard.local', password: 'focusguard123' })
    });

    if (res.ok) {
      const data = await res.json();
      authToken = data.accessToken;
      if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
        await chrome.storage.local.set({ 'focusguard_token': authToken });
      }
      return authToken;
    }
  } catch (e) {
    console.warn('[FocusGuard Extension] Auth exchange error:', e);
  }
  return null;
}

// Initialize Session Tracker with 60s idle threshold
const sessionTracker = new SessionTracker({
  idleThresholdSeconds: 60,
  onUsageTick: async (tick) => {
    // Guard against sleep jump: cap single tick delta to 60 seconds
    const safeDelta = Math.min(tick.deltaSeconds, 60);
    policyEngine.updateUsage(tick.domain, safeDelta);
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

function buildBlockPageUrl(normDomain, evalResult) {
  return chrome.runtime.getURL(
    `pages/block.html?target=${encodeURIComponent(normDomain)}` +
    `&reason=${encodeURIComponent(evalResult.reason || 'Attention Budget Reached')}` +
    `&policy=${encodeURIComponent(evalResult.policyName || 'FocusGuard Policy')}` +
    `&used=${encodeURIComponent(evalResult.usedMinutes || 30)}` +
    `&limit=${encodeURIComponent(evalResult.limitMinutes || 30)}` +
    `&reset=${encodeURIComponent(evalResult.nextReset || '12:00 AM')}`
  );
}

/**
 * Redirects tab to the FocusGuard block page, registers network-level DNR rule, and emits an enforcement event.
 */
async function redirectToBlockPage(tabId, urlOrDomain, evalResult) {
  const normDomain = typeof DomainMatcher !== 'undefined' ? DomainMatcher.normalizeDomain(urlOrDomain) : urlOrDomain;
  const blockUrl = buildBlockPageUrl(normDomain, evalResult);

  // Instantly enforce at network level via DeclarativeNetRequest so reload/new tabs cannot bypass
  if (typeof chrome !== 'undefined' && chrome.declarativeNetRequest && typeof DNRPolicyCompiler !== 'undefined') {
    const ruleId = DNRPolicyCompiler.getDeterministicRuleId(normDomain);
    chrome.declarativeNetRequest.updateDynamicRules({
      removeRuleIds: [ruleId],
      addRules: [{
        id: ruleId,
        priority: 95,
        action: {
          type: 'redirect',
          redirect: { url: blockUrl }
        },
        condition: {
          urlFilter: `||${normDomain}^`,
          resourceTypes: ['main_frame']
        }
      }]
    }).catch(() => {});
  }

  const devId = await getOrCreateDeviceId();
  const eventId = (typeof crypto !== 'undefined' && crypto.randomUUID) ? crypto.randomUUID() : ('evt_' + Date.now() + '_' + Math.random().toString(36).substring(2, 9));
  const blockEvent = {
    id: eventId,
    deviceId: devId,
    eventType: 'DOMAIN_BLOCKED',
    domain: normDomain,
    reason: evalResult.reason || 'Attention budget reached',
    timestamp: new Date().toISOString(),
    metadata: {
      policyName: evalResult.policyName,
      usedMinutes: evalResult.usedMinutes,
      limitMinutes: evalResult.limitMinutes
    }
  };

  await policyCache.enqueueOfflineEvent(blockEvent).catch((err) => {
    console.warn('[FocusGuard Extension] Error enqueuing block event:', err);
  });

  // Attempt immediate flush if online
  flushOfflineEvents().catch(() => {});

  if (typeof chrome !== 'undefined' && chrome.tabs && tabId) {
    chrome.tabs.update(tabId, { url: blockUrl }).catch(() => {});
  }
}

/**
 * Drains and synchronizes queued offline events to the backend with atomic deduplication.
 */
async function flushOfflineEvents() {
  try {
    const cached = await policyCache.getStoredData();
    const queue = cached.offlineQueue || [];
    if (queue.length === 0) return;

    const token = await getOrFetchAuthToken();
    if (!token) return;

    await setNetworkState('SYNCING');
    const toFlush = queue.slice(0, 50);

    const res = await fetch(`${API_BASE}/events/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({ events: toFlush })
    });

    if (res.ok) {
      await policyCache.drainOfflineQueue(toFlush.map(e => e.id));
      await setNetworkState('ONLINE');
      console.log(`[FocusGuard Extension] Flushed ${toFlush.length} offline events to cloud.`);
    } else {
      await setNetworkState('DEGRADED');
    }
  } catch (e) {
    await setNetworkState('OFFLINE');
    console.warn('[FocusGuard Extension] Flush offline events deferred (offline mode).');
  }
}

/**
 * Initializes policies and connects WebSocket.
 */
async function initializeExtension() {
  console.log('[FocusGuard Extension] Initializing service worker...');

  // 1. Authenticate / load token
  await getOrFetchAuthToken();

  // 2. Load cached policies and state
  const cached = await policyCache.getStoredData();
  currentPolicyVersion = cached.version || 1;
  policyEngine.setPolicies(cached.policies);
  policyEngine.setTodayUsage(cached.todayUsage);
  policyEngine.setFocusSession(cached.focusSession);

  // 3. Fetch fresh policies from backend
  await fetchPoliciesFromServer();

  // 4. Connect real-time WebSocket hub
  await connectWebSocket();

  // 5. Flush any offline events accumulated while worker was sleeping
  await flushOfflineEvents();

  // 6. Setup periodic usage sync alarm (every 1 minute)
  if (chrome.alarms) {
    chrome.alarms.create('fg_usage_sync', { periodInMinutes: 1 });
  }
}

/**
 * Fetches versioned policies from server with atomic verification.
 */
async function fetchPoliciesFromServer() {
  try {
    const token = await getOrFetchAuthToken();
    const headers = token ? { 'Authorization': `Bearer ${token}` } : {};
    const resp = await fetch(`${API_BASE}/policies`, { headers, credentials: 'omit' });
    if (resp.ok) {
      const data = await resp.json();
      const policies = Array.isArray(data) ? data : (data.policies || []);
      const versionHeader = resp.headers.get('X-Policy-Version');
      const serverVersion = versionHeader ? parseInt(versionHeader, 10) : (data.version || (currentPolicyVersion + 1));

      // Atomic Update: Compile rules BEFORE persisting or activating
      let dynamicRules = [];
      if (typeof DNRPolicyCompiler !== 'undefined') {
        dynamicRules = DNRPolicyCompiler.compileDynamicRules(policies, policyEngine.todayUsage);
      }

      const dnrSuccess = typeof DNRPolicyCompiler !== 'undefined'
        ? await DNRPolicyCompiler.syncWithBrowser(dynamicRules)
        : true;

      if (!dnrSuccess && dynamicRules.length > 0) {
        console.error('[FocusGuard Extension] DNR compile/sync failed; retaining working policy.');
        return;
      }

      currentPolicyVersion = serverVersion;
      policyEngine.setPolicies(policies);
      await policyCache.updatePolicies(policies, serverVersion);
      console.log(`[FocusGuard Extension] Synchronized policy v${serverVersion} (${policies.length} policies).`);
    }
  } catch (err) {
    console.warn('[FocusGuard Extension] Backend unreachable; operating in 100% offline cache mode.', err);
  }
}

let heartbeatInterval = null;

function startHeartbeatLoop() {
  if (heartbeatInterval) clearInterval(heartbeatInterval);
  heartbeatInterval = setInterval(async () => {
    if (wsConnection && wsConnection.readyState === WebSocket.OPEN) {
      const devId = await getOrCreateDeviceId();
      wsConnection.send(JSON.stringify({
        type: 'HEARTBEAT',
        deviceId: devId,
        platform: 'WEB_EXTENSION',
        timestamp: Date.now()
      }));
    }
  }, 10000);
}

function scheduleReconnect() {
  if (reconnectTimeoutId) clearTimeout(reconnectTimeoutId);
  reconnectAttempts++;
  // Jittered exponential backoff: 2s * 1.5^(attempt-1) up to 60s max, ±20% jitter
  const baseDelay = Math.min(60000, 2000 * Math.pow(1.5, Math.min(reconnectAttempts - 1, 8)));
  const jitter = baseDelay * (0.8 + Math.random() * 0.4);
  const delayMs = Math.round(jitter);

  setNetworkState('RECONNECTING');
  reconnectTimeoutId = setTimeout(() => {
    connectWebSocket();
  }, delayMs);

  if (typeof chrome !== 'undefined' && chrome.alarms) {
    chrome.alarms.create('fg_reconnect_watchdog', { delayInMinutes: Math.max(0.5, delayMs / 60000) });
  }
}

/**
 * Real-time WebSocket connection for instant remote focus and limits.
 */
async function connectWebSocket() {
  if (wsConnection) {
    try { wsConnection.close(); } catch (e) {}
  }

  try {
    const token = await getOrFetchAuthToken();
    const wsUrl = token ? `${WS_URL}?token=${token}` : WS_URL;
    wsConnection = new WebSocket(wsUrl);

    wsConnection.onopen = async () => {
      console.log('[FocusGuard Extension] Real-time WebSocket connected');
      reconnectAttempts = 0;
      await setNetworkState('ONLINE');
      const devId = await getOrCreateDeviceId();
      wsConnection.send(JSON.stringify({
        type: 'REGISTER_DEVICE',
        deviceId: devId,
        platform: 'WEB_EXTENSION'
      }));
      startHeartbeatLoop();
      flushOfflineEvents();
    };

    wsConnection.onclose = () => {
      console.log('[FocusGuard Extension] WS closed, scheduling reconnect...');
      if (heartbeatInterval) clearInterval(heartbeatInterval);
      scheduleReconnect();
    };

    wsConnection.onerror = (err) => {
      console.warn('[FocusGuard Extension] WS error:', err);
    };

    wsConnection.onmessage = async (msg) => {
      try {
        const raw = JSON.parse(msg.data);
        console.log('[FocusGuard Extension] WS event received:', raw);
        const eventName = raw.event || raw.type;
        const data = raw.payload || raw;

        if (eventName === 'POLICY_UPDATED' || eventName === 'POLICY_CREATED' || eventName === 'POLICY_DELETED') {
          await fetchPoliciesFromServer();
        } else if (eventName === 'FOCUS_STARTED' || eventName === 'FOCUS_SESSION_STARTED') {
          policyEngine.setFocusSession({
            isActive: true,
            name: data.name || 'Remote Focus Session',
            durationMinutes: data.durationMinutes || 45,
            allowedDomains: data.allowedDomains || ['github.com', 'stackoverflow.com']
          });
          await policyCache.setFocusSession(policyEngine.focusSession);
          if (sessionTracker.currentTabId && sessionTracker.currentDomain) {
            const evalResult = policyEngine.evaluate(sessionTracker.currentDomain);
            if (evalResult.action === 'BLOCK') {
              redirectToBlockPage(sessionTracker.currentTabId, sessionTracker.currentDomain, evalResult);
            }
          }
        } else if (eventName === 'FOCUS_ENDED' || eventName === 'FOCUS_SESSION_ENDED') {
          policyEngine.setFocusSession(null);
          await policyCache.setFocusSession(null);
        } else if (eventName === 'LIMIT_REACHED') {
          policyEngine.updateUsage(data.targetValue, data.limitSeconds || 1800);
          if (sessionTracker.currentTabId && sessionTracker.currentDomain && 
              DomainMatcher.isDomainMatch(sessionTracker.currentDomain, data.targetValue)) {
            const evalResult = policyEngine.evaluate(sessionTracker.currentDomain);
            redirectToBlockPage(sessionTracker.currentTabId, sessionTracker.currentDomain, evalResult);
          }
        }
      } catch (e) {
        console.error('[FocusGuard Extension] Error handling WS message', e);
      }
    };
  } catch (err) {
    console.warn('[FocusGuard Extension] WS initialization failed:', err);
    scheduleReconnect();
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

// Periodic Alarm for Incremental Usage Synchronization & Reconnect Watchdog
if (chrome.alarms) {
  chrome.alarms.onAlarm.addListener(async (alarm) => {
    if (alarm.name === 'fg_reconnect_watchdog') {
      if (!wsConnection || wsConnection.readyState !== WebSocket.OPEN) {
        connectWebSocket();
      }
    }

    if (alarm.name === 'fg_usage_sync') {
      try {
        const token = await getOrFetchAuthToken();
        const devId = await getOrCreateDeviceId();
        const cached = await policyCache.getStoredData();
        const todayUsage = cached.todayUsage || {};
        const lastSynced = cached.lastSyncedUsage || {};
        const newSynced = { ...lastSynced };

        const usageDeltas = [];
        const todayStr = new Date().toISOString().split('T')[0];

        for (const [target, sec] of Object.entries(todayUsage)) {
          const prev = lastSynced[target] || 0;
          const delta = sec - prev;
          if (delta > 0) {
            usageDeltas.push({
              id: `ext_delta_${devId}_${target}_${Date.now()}`,
              targetValue: target,
              durationSeconds: delta,
              date: todayStr
            });
            newSynced[target] = sec;
          }
        }

        if (usageDeltas.length > 0) {
          const headers = { 'Content-Type': 'application/json' };
          if (token) headers['Authorization'] = `Bearer ${token}`;

          const res = await fetch(`${API_BASE}/usage/sync`, {
            method: 'POST',
            headers: headers,
            body: JSON.stringify({
              deviceId: devId,
              idempotencyKey: `ext_batch_${devId}_${Date.now()}`,
              usageDeltas: usageDeltas
            })
          });

          if (res.ok) {
            await policyCache.setLastSyncedUsage(newSynced);
            console.log(`[FocusGuard Extension] Incremental usage synced (${usageDeltas.length} targets).`);
          }
        }

        // Also flush any pending offline events
        await flushOfflineEvents();
      } catch (err) {
        console.warn('[FocusGuard Extension] Periodic sync skipped (offline mode).');
      }
    }
  });
}

// ---------------- Real-time Active Content Script Channel ----------------
if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.onConnect) {
  chrome.runtime.onConnect.addListener((port) => {
    if (port.name !== 'focusguard-tracker') return;

    port.onMessage.addListener(async (msg) => {
      const tabId = port.sender?.tab?.id;
      if (!tabId || !msg || !msg.url) return;

      const normDomain = typeof DomainMatcher !== 'undefined' 
        ? DomainMatcher.normalizeDomain(msg.hostname || msg.url) 
        : (msg.hostname || 'unknown');

      if (msg.type === 'PAGE_ACTIVE_TICK') {
        policyEngine.updateUsage(normDomain, 1);
        await policyCache.setTodayUsage(policyEngine.todayUsage);

        const evalResult = policyEngine.evaluate(msg.url);
        if (evalResult.action === 'BLOCK') {
          const blockUrl = buildBlockPageUrl(normDomain, evalResult);
          try {
            port.postMessage({ type: 'ENFORCE_BLOCK', blockUrl });
          } catch (e) {}
          redirectToBlockPage(tabId, msg.url, evalResult);
        }
      } else if (msg.type === 'SPA_NAVIGATION') {
        const evalResult = policyEngine.evaluate(msg.url);
        if (evalResult.action === 'BLOCK') {
          const blockUrl = buildBlockPageUrl(normDomain, evalResult);
          try {
            port.postMessage({ type: 'ENFORCE_BLOCK', blockUrl });
          } catch (e) {}
          redirectToBlockPage(tabId, msg.url, evalResult);
        }
      }
    });
  });
}

// ---------------- Runtime Message Interceptors (Popup / UI Bridge) ----------------
if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.onMessage) {
  chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.type === 'GET_STATUS') {
      (async () => {
        const devId = await getOrCreateDeviceId();
        const cached = await policyCache.getStoredData();
        const stored = await chrome.storage.local.get(['fg_pairing_status', 'focusguard_device_name', 'focusguard_token']);
        sendResponse({
          deviceId: devId,
          deviceName: stored.focusguard_device_name || 'Browser Extension',
          pairingStatus: stored.fg_pairing_status || (stored.focusguard_token ? 'PAIRED' : 'UNPAIRED'),
          networkState: currentNetworkState,
          policyVersion: currentPolicyVersion,
          policiesCount: (cached.policies || []).length,
          offlineQueueSize: (cached.offlineQueue || []).length,
          focusSession: cached.focusSession
        });
      })();
      return true; // Keep async channel open
    }

    if (request.type === 'SUBMIT_PAIRING_CODE') {
      (async () => {
        try {
          const devId = await getOrCreateDeviceId();
          let code = (request.code || '').trim().toUpperCase().replace(/\s+/g, '').replace(/_/g, '');
          if (code.startsWith('FG') && !code.startsWith('FG-')) {
            code = 'FG-' + code.slice(2);
          } else if (!code.startsWith('FG-') && code.length > 0) {
            code = 'FG-' + code;
          }

          const reqRes = await fetch(`${API_BASE}/pairing/request`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              pairingCode: code,
              deviceName: devName,
              platform: 'BROWSER_EXTENSION',
              clientType: 'EXTENSION',
              appVersion: '2.0.0',
              publicKey: 'simulated_ext_pubkey_' + devId,
              keyAlgorithm: 'Ed25519'
            })
          });

          if (!reqRes.ok) {
            const err = await reqRes.json().catch(() => ({}));
            sendResponse({ success: false, error: err.error?.message || 'Invalid or expired pairing code' });
            return;
          }

          const reqData = await reqRes.json();
          const sessionId = reqData.sessionId;

          let approved = false;
          for (let i = 0; i < 30; i++) {
            await new Promise(r => setTimeout(r, 1000));
            const pollRes = await fetch(`${API_BASE}/pairing/sessions/${sessionId}/status`);
            if (pollRes.ok) {
              const statusData = await pollRes.json();
              if (statusData.status === 'APPROVED') {
                await chrome.storage.local.set({
                  focusguard_token: statusData.deviceToken,
                  focusguard_device_token: statusData.deviceToken,
                  focusguard_device_id: statusData.deviceId,
                  fg_pairing_status: 'PAIRED'
                });
                authToken = statusData.deviceToken;
                cachedDeviceId = statusData.deviceId;
                approved = true;
                await initializeExtension();
                sendResponse({ success: true, deviceId: statusData.deviceId });
                break;
              } else if (statusData.status === 'REJECTED') {
                sendResponse({ success: false, error: 'Pairing request was rejected by account owner' });
                return;
              } else if (statusData.status === 'CANCELLED' || statusData.status === 'EXPIRED') {
                sendResponse({ success: false, error: 'Pairing session expired or cancelled' });
                return;
              }
            }
          }

          if (!approved) {
            sendResponse({ success: false, error: 'Pairing timed out waiting for owner approval' });
          }
        } catch (e) {
          sendResponse({ success: false, error: e.message || 'Pairing error' });
        }
      })();
      return true;
    }
  });
}

// Lifecycle Init
initializeExtension();
