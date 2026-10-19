/**
 * FocusGuard Web Command Center — Enterprise Client Engine
 * Real-time WebSocket synchronization, fleet attention control, and live website analytics.
 */

const API_BASE = "http://localhost:8080/api/v1";
const WS_BASE = "ws://localhost:8080/ws";

// Core Reactive State
const state = {
  token: localStorage.getItem("focusguard_token") || null,
  user: null,
  
  // Real-time Focus Session
  isFocusActive: false,
  selectedFocusMins: 45,
  focusRemainingSeconds: 2700,
  focusTimerInterval: null,
  activeSessionId: null,

  // Telemetry & Analytics
  websiteAnalytics: { websites: [], formattedTime: "0s", totalSeconds: 0 },
  dailyAnalytics: null,
  currentCategoryFilter: "ALL",
  searchQuery: "",

  // Fleet & Policies
  devices: [],
  policies: [],
  auditLogs: [],

  // Pairing
  pairingTimerInterval: null,
  pairingSecondsLeft: 300,

  // WebSocket
  ws: null,
  wsConnected: false,
  reconnectAttempts: 0
};

// ============================================================================
// INITIALIZATION
// ============================================================================
document.addEventListener("DOMContentLoaded", async () => {
  await ensureAuthentication();
  setupWebSocket();
  await refreshAllData();

  // Periodic silent polling every 4 seconds to ensure data freshness
  setInterval(() => {
    refreshSilent();
  }, 4000);
});

async function ensureAuthentication() {
  if (state.token) {
    return;
  }

  try {
    const res = await fetch(`${API_BASE}/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: "demo@focusguard.local", password: "focusguard123" })
    });

    if (res.ok) {
      const data = await res.json();
      state.token = data.accessToken;
      state.user = data.user;
      localStorage.setItem("focusguard_token", state.token);
      if (data.user?.email) {
        document.getElementById("user-display-email").innerText = data.user.email;
      }
    }
  } catch (err) {
    console.warn("[FocusGuard] Auth failed, running in guest mode", err);
  }
}

// ============================================================================
// WEBSOCKET REAL-TIME HUB
// ============================================================================
function setupWebSocket() {
  if (state.ws && (state.ws.readyState === WebSocket.OPEN || state.ws.readyState === WebSocket.CONNECTING)) {
    return;
  }

  const tokenParam = state.token ? `?token=${encodeURIComponent(state.token)}` : "";
  const wsUrl = `${WS_BASE}${tokenParam}`;

  try {
    state.ws = new WebSocket(wsUrl);

    state.ws.onopen = () => {
      state.wsConnected = true;
      state.reconnectAttempts = 0;
      updateSyncStatusUI(true);
      console.log("[FocusGuard WS] Real-time fleet sync connected.");
    };

    state.ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        handleIncomingEvent(msg);
      } catch (e) {
        console.warn("[FocusGuard WS] Unparseable message:", event.data);
      }
    };

    state.ws.onclose = () => {
      state.wsConnected = false;
      updateSyncStatusUI(false);
      scheduleWsReconnect();
    };

    state.ws.onerror = () => {
      state.wsConnected = false;
      updateSyncStatusUI(false);
    };
  } catch (err) {
    console.warn("[FocusGuard WS] Connection error:", err);
    scheduleWsReconnect();
  }
}

function scheduleWsReconnect() {
  const backoff = Math.min(30000, 1000 * Math.pow(1.5, state.reconnectAttempts++));
  setTimeout(setupWebSocket, backoff);
}

function updateSyncStatusUI(isLive) {
  const pill = document.getElementById("ws-sync-pill");
  const text = document.getElementById("ws-status-text");
  if (!pill || !text) return;

  if (isLive) {
    pill.className = "status-pill status-ws-live";
    text.innerText = "Real-Time Sync Active";
  } else {
    pill.className = "status-pill";
    pill.style.borderColor = "rgba(245, 158, 11, 0.3)";
    pill.style.color = "#fbbf24";
    text.innerText = "Reconnecting Sync...";
  }
}

function handleIncomingEvent(msg) {
  const eventType = msg.event || msg.type;
  console.log("[FocusGuard WS Event]", eventType, msg.payload);

  switch (eventType) {
    case "FOCUS_STARTED":
      applyFocusActiveState(msg.payload?.durationMinutes || 45, msg.payload?.remainingSeconds);
      showToast("🔒 Deep Work Focus Lockdown Active Across All Devices!", "success");
      break;

    case "FOCUS_ENDED":
      applyFocusStandbyState();
      showToast("Focus Lockdown Ended • Normal State Restored", "info");
      break;

    case "POLICY_UPDATED":
    case "POLICY_CREATED":
    case "POLICY_DELETED":
      fetchPolicies();
      fetchWebsitesAnalytics();
      showToast("Policy rules updated and synced across fleet", "info");
      break;

    case "DEVICE_HEARTBEAT":
      fetchDevices();
      break;

    case "TAMPER_ALERT":
    case "EXTENSION_MISSING_WARNING":
      showToast(`⚠️ Tamper Warning: ${msg.payload?.warning || "Protection state degraded"}`, "alert");
      break;

    case "REMOTE_COMMAND":
      fetchDevices();
      if (msg.protectionState === "LOCKED" || msg.commandType === "STOP_APP" || msg.commandType === "LOCKDOWN_DEVICE") {
        showToast(`🛑 Remote Lockdown: ${msg.deviceId === 'ALL' ? 'All fleet devices' : 'Device'} stopped by admin!`, "alert");
      } else if (msg.protectionState === "PROTECTED" || msg.commandType === "RESUME_APP" || msg.commandType === "UNLOCK_DEVICE") {
        showToast(`🔓 Protection Resumed: ${msg.deviceId === 'ALL' ? 'All fleet devices' : 'Device'} unlocked by admin!`, "success");
      }
      break;

    default:
      break;
  }
}

// ============================================================================
// DATA FETCHING & SYNCHRONIZATION
// ============================================================================
async function refreshAllData() {
  await Promise.all([
    checkActiveFocus(),
    fetchWebsitesAnalytics(),
    fetchDailyAnalytics(),
    fetchDevices(),
    fetchPolicies(),
    fetchAuditLogs()
  ]);
}

async function refreshSilent() {
  if (!state.token) return;
  try {
    await Promise.all([
      fetchWebsitesAnalytics(true),
      fetchDailyAnalytics(true)
    ]);
  } catch (e) {}
}

window.triggerFleetSync = async function() {
  showToast("Synchronizing fleet telemetry across devices...", "info");
  await refreshAllData();
  showToast("Fleet synchronized successfully!", "success");
};

// ============================================================================
// FOCUS LOCKDOWN CONTROLLER
// ============================================================================
window.selectFocusPreset = function(mins) {
  if (state.isFocusActive) return;
  state.selectedFocusMins = mins;
  state.focusRemainingSeconds = mins * 60;

  // Update button active states
  document.querySelectorAll(".btn-preset").forEach(btn => {
    btn.classList.toggle("active", parseInt(btn.getAttribute("data-mins"), 10) === mins);
  });

  updateTimerDigits(state.focusRemainingSeconds);
};

window.handleFocusButtonClick = async function() {
  if (state.isFocusActive) {
    await endFocusLockdown();
  } else {
    await startFocusLockdown(state.selectedFocusMins);
  }
};

async function startFocusLockdown(mins) {
  try {
    const res = await fetch(`${API_BASE}/focus/start`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${state.token}`
      },
      body: JSON.stringify({
        durationMinutes: mins,
        reason: "Deep Work Attention Session"
      })
    });

    if (res.ok) {
      const data = await res.json();
      state.activeSessionId = data.id;
      applyFocusActiveState(mins, mins * 60);
      showToast(`🔒 Deep Work Lockdown Enforced (${mins}m)!`, "success");
    } else {
      showToast("Failed to initiate focus lockdown", "alert");
    }
  } catch (err) {
    showToast("Network error starting focus", "alert");
  }
}

window.endFocusLockdown = async function() {
  try {
    const res = await fetch(`${API_BASE}/focus/end`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${state.token}`
      }
    });

    if (res.ok) {
      applyFocusStandbyState();
      showToast("Fleet attention lockdown released", "info");
    }
  } catch (err) {
    showToast("Error releasing focus session", "alert");
  }
};

async function checkActiveFocus() {
  try {
    const res = await fetch(`${API_BASE}/focus/active`, {
      headers: { "Authorization": `Bearer ${state.token}` }
    });
    if (res.ok) {
      const data = await res.json();
      if (data.active && data.session) {
        state.activeSessionId = data.session.id;
        applyFocusActiveState(data.session.durationMinutes, data.session.remainingSeconds);
      } else {
        applyFocusStandbyState();
      }
    }
  } catch (e) {}
}

function applyFocusActiveState(durationMins, remainingSec) {
  state.isFocusActive = true;
  state.focusRemainingSeconds = remainingSec !== undefined ? remainingSec : durationMins * 60;

  const heroCard = document.getElementById("focus-hero-card");
  const modeLabel = document.getElementById("focus-mode-label");
  const btnStart = document.getElementById("btn-toggle-focus");
  const btnCancel = document.getElementById("btn-cancel-focus");
  const subtext = document.getElementById("timer-subtext");

  if (heroCard) heroCard.classList.add("focus-active");
  if (modeLabel) modeLabel.innerText = "ACTIVE LOCKDOWN • DISTRACTIONS SEALED";
  if (btnStart) btnStart.style.display = "none";
  if (btnCancel) btnCancel.style.display = "flex";
  if (subtext) subtext.innerText = "REMAINING ATTENTION LOCK";

  startCountdownTicker();
}

function applyFocusStandbyState() {
  state.isFocusActive = false;
  clearInterval(state.focusTimerInterval);
  state.focusTimerInterval = null;

  const heroCard = document.getElementById("focus-hero-card");
  const modeLabel = document.getElementById("focus-mode-label");
  const btnStart = document.getElementById("btn-toggle-focus");
  const btnCancel = document.getElementById("btn-cancel-focus");
  const subtext = document.getElementById("timer-subtext");

  if (heroCard) heroCard.classList.remove("focus-active");
  if (modeLabel) modeLabel.innerText = "STANDBY • NORMAL BROWSING";
  if (btnStart) btnStart.style.display = "flex";
  if (btnCancel) btnCancel.style.display = "none";
  if (subtext) subtext.innerText = "SELECTED DURATION";

  state.focusRemainingSeconds = state.selectedFocusMins * 60;
  updateTimerDigits(state.focusRemainingSeconds);
}

function startCountdownTicker() {
  if (state.focusTimerInterval) clearInterval(state.focusTimerInterval);

  updateTimerDigits(state.focusRemainingSeconds);

  state.focusTimerInterval = setInterval(() => {
    state.focusRemainingSeconds--;
    if (state.focusRemainingSeconds <= 0) {
      applyFocusStandbyState();
      showToast("🎉 Focus Session Complete! Excellent work.", "success");
      return;
    }
    updateTimerDigits(state.focusRemainingSeconds);
  }, 1000);
}

function updateTimerDigits(totalSeconds) {
  const el = document.getElementById("timer-digits");
  if (!el) return;

  const m = Math.floor(totalSeconds / 60);
  const s = totalSeconds % 60;
  el.innerText = `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

// ============================================================================
// WEBSITE ATTENTION ANALYTICS TABLE
// ============================================================================
async function fetchWebsitesAnalytics(silent = false) {
  if (!state.token) return;
  try {
    const res = await fetch(`${API_BASE}/analytics/websites`, {
      headers: { "Authorization": `Bearer ${state.token}` }
    });
    if (res.ok) {
      state.websiteAnalytics = await res.json();
      renderWebsitesTable();
    }
  } catch (err) {
    if (!silent) console.warn("Failed fetching website analytics", err);
  }
}

function renderWebsitesTable() {
  const tbody = document.getElementById("websites-table-body");
  const totalTimeEl = document.getElementById("kpi-total-web-time");
  const countBadge = document.getElementById("kpi-web-count-badge");
  const tabBadge = document.getElementById("tab-web-count");
  if (!tbody) return;

  const allWebsites = state.websiteAnalytics?.websites || [];
  const totalFormatted = state.websiteAnalytics?.formattedTime || "0s";

  if (totalTimeEl) totalTimeEl.innerText = totalFormatted;
  if (countBadge) countBadge.innerText = `${allWebsites.length} Domains`;
  if (tabBadge) tabBadge.innerText = allWebsites.length;

  // Update Category Count Chips
  const distractionCount = allWebsites.filter(w => w.isDistraction || w.category.includes("Social") || w.category.includes("Entertainment")).length;
  const workCount = allWebsites.filter(w => w.category.includes("Development") || w.category.includes("Engineering") || w.category.includes("Work")).length;
  const academicCount = allWebsites.filter(w => w.category.includes("Academic") || w.category.includes("Education")).length;

  const chipAll = document.getElementById("chip-count-all");
  const chipDist = document.getElementById("chip-count-distraction");
  const chipWork = document.getElementById("chip-count-work");
  const chipAcad = document.getElementById("chip-count-academic");

  if (chipAll) chipAll.innerText = allWebsites.length;
  if (chipDist) chipDist.innerText = distractionCount;
  if (chipWork) chipWork.innerText = workCount;
  if (chipAcad) chipAcad.innerText = academicCount;

  // Filter list
  let filtered = allWebsites;

  if (state.currentCategoryFilter === "DISTRACTION") {
    filtered = filtered.filter(w => w.isDistraction || w.category.includes("Social") || w.category.includes("Entertainment"));
  } else if (state.currentCategoryFilter === "WORK") {
    filtered = filtered.filter(w => w.category.includes("Development") || w.category.includes("Engineering") || w.category.includes("Work"));
  } else if (state.currentCategoryFilter === "ACADEMIC") {
    filtered = filtered.filter(w => w.category.includes("Academic") || w.category.includes("Education"));
  }

  if (state.searchQuery) {
    const q = state.searchQuery.toLowerCase();
    filtered = filtered.filter(w => w.domain.toLowerCase().includes(q) || w.category.toLowerCase().includes(q));
  }

  if (filtered.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="5" class="table-empty-row">
          <span>No websites matching current filter or search criteria.</span>
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = filtered.map(item => {
    let icon = "🌐";
    let catClass = "badge-purple";
    if (item.category.includes("Social") || item.category.includes("Entertainment")) {
      icon = "📺";
      catClass = "badge-red";
    } else if (item.category.includes("Development") || item.category.includes("Engineering")) {
      icon = "💻";
      catClass = "badge-green";
    } else if (item.category.includes("Education") || item.category.includes("Academic")) {
      icon = "🎓";
      catClass = "badge-blue";
    } else if (item.category.includes("Work")) {
      icon = "💼";
      catClass = "badge-purple";
    }

    // Budget bar
    let budgetHtml = "";
    if (item.limitSeconds && item.limitSeconds > 0) {
      const limitMins = Math.round(item.limitSeconds / 60);
      const pct = Math.min(100, Math.round((item.totalSeconds / item.limitSeconds) * 100));
      const barColor = item.isExceeded ? "#ef4444" : (pct >= 75 ? "#f59e0b" : "#10b981");

      budgetHtml = `
        <div style="display: flex; flex-direction: column; gap: 4px;">
          <div style="display: flex; justify-content: space-between; font-size: 11px; font-family: var(--font-mono);">
            <span style="color: ${barColor}; font-weight: 700;">${item.formattedTime} / ${limitMins}m</span>
            <span style="color: var(--text-muted);">${pct}%</span>
          </div>
          <div class="kpi-progress-bar" style="height: 5px;">
            <div style="width: ${pct}%; height: 100%; background: ${barColor}; border-radius: 999px;"></div>
          </div>
          ${item.policyName ? `<span style="font-size: 10px; color: var(--text-muted);">${escapeHtml(item.policyName)}</span>` : ""}
        </div>
      `;
    } else {
      budgetHtml = `<span style="font-size: 12px; color: var(--text-muted);">No Cap (Passive Tracking)</span>`;
    }

    return `
      <tr>
        <td>
          <div class="domain-cell">
            <div class="domain-icon" style="background: rgba(255,255,255,0.04);">${icon}</div>
            <div class="domain-meta">
              <span class="domain-name">${escapeHtml(item.domain)}</span>
              <span class="domain-session-count">${item.totalSeconds}s continuous session</span>
            </div>
          </div>
        </td>
        <td>
          <span class="kpi-badge ${catClass}">${escapeHtml(item.category)}</span>
        </td>
        <td>
          <span class="time-cell-val">${item.formattedTime}</span>
        </td>
        <td>
          ${budgetHtml}
        </td>
        <td style="text-align: right;">
          ${item.isExceeded 
            ? `<span class="kpi-badge badge-red" style="font-size: 10px;">SEALED</span>`
            : `<button class="btn btn-sm btn-outline" onclick="window.quickAddDomainRuleFor('${escapeHtml(item.domain)}')">Cap (30m)</button>`
          }
        </td>
      </tr>
    `;
  }).join("");
}

window.applyCategoryFilter = function(filter) {
  state.currentCategoryFilter = filter;
  document.querySelectorAll(".filter-chip").forEach(c => c.classList.remove("active"));
  const activeChip = document.getElementById(`fchip-${filter}`);
  if (activeChip) activeChip.classList.add("active");
  renderWebsitesTable();
};

window.handleWebsiteSearch = function(val) {
  state.searchQuery = val.trim();
  renderWebsitesTable();
};

// ============================================================================
// DAILY KPI & ATTENTION SCORE
// ============================================================================
async function fetchDailyAnalytics(silent = false) {
  if (!state.token) return;
  try {
    const res = await fetch(`${API_BASE}/analytics/daily`, {
      headers: { "Authorization": `Bearer ${state.token}` }
    });
    if (res.ok) {
      state.dailyAnalytics = await res.json();
      renderKPICards();
    }
  } catch (err) {
    if (!silent) console.warn("Failed fetching daily analytics", err);
  }
}

function renderKPICards() {
  const d = state.dailyAnalytics;
  if (!d) return;

  // Distraction KPI
  const distUsedEl = document.getElementById("kpi-distraction-used");
  const distTotalEl = document.getElementById("kpi-budget-total");
  const budgetFill = document.getElementById("kpi-budget-fill");

  if (distUsedEl) distUsedEl.innerText = `${d.budgetUsedMinutes || 0}m`;
  if (distTotalEl) distTotalEl.innerText = `/ ${d.budgetTotalMinutes || 30} min cap`;

  const pct = d.budgetTotalMinutes > 0 ? Math.min(100, Math.round((d.budgetUsedMinutes / d.budgetTotalMinutes) * 100)) : 0;
  if (budgetFill) {
    budgetFill.style.width = `${pct}%`;
    budgetFill.style.background = pct >= 90 ? "#ef4444" : (pct >= 70 ? "#f59e0b" : "#06b6d4");
  }

  // Attention Score KPI
  if (d.attentionScore) {
    const scoreVal = document.getElementById("kpi-score-val");
    const scoreRating = document.getElementById("kpi-score-rating");
    if (scoreVal) scoreVal.innerHTML = `${d.attentionScore.overallScore}<span class="score-denom">/100</span>`;
    if (scoreRating) {
      scoreRating.innerText = d.attentionScore.rating || "HEALTHY";
      scoreRating.className = d.attentionScore.overallScore >= 80 ? "kpi-badge badge-green" : (d.attentionScore.overallScore >= 60 ? "kpi-badge badge-purple" : "kpi-badge badge-red");
    }
  }
}

// ============================================================================
// DEVICES FLEET VIEW
// ============================================================================
async function fetchDevices() {
  if (!state.token) return;
  try {
    const res = await fetch(`${API_BASE}/devices`, {
      headers: { "Authorization": `Bearer ${state.token}` }
    });
    if (res.ok) {
      state.devices = await res.json();
      renderDevicesGrid();
    }
  } catch (e) {}
}

function renderDevicesGrid() {
  const container = document.getElementById("devices-grid-container");
  const countEl = document.getElementById("kpi-devices-count");
  const tabBadge = document.getElementById("tab-devices-badge");
  if (!container) return;

  const list = state.devices || [];
  if (countEl) countEl.innerText = list.length;
  if (tabBadge) tabBadge.innerText = list.length;

  if (list.length === 0) {
    container.innerHTML = `<p class="table-empty-row">No devices currently enrolled. Click "Pair Device" to connect.</p>`;
    return;
  }

  container.innerHTML = list.map(dev => {
    const isOnline = dev.status === "ACTIVE" || dev.status === "ONLINE";
    const isExtension = dev.platform === "WEB_EXTENSION" || dev.osVersion?.includes("Extension");
    const isLocked = dev.protectionState === "LOCKED";

    return `
      <div class="device-card" style="${isLocked ? 'border-color: rgba(239, 68, 68, 0.4); background: rgba(239, 68, 68, 0.04);' : ''}">
        <div class="device-card-header">
          <div class="device-title-row">
            <div class="device-icon-box" style="${isLocked ? 'background: rgba(239, 68, 68, 0.15); color: #f87171;' : ''}">
              ${isExtension 
                ? `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/></svg>`
                : `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>`
              }
            </div>
            <div>
              <div class="device-name">${escapeHtml(dev.deviceName || dev.name || "FocusGuard Client")}</div>
              <div class="device-platform">${escapeHtml(dev.platform)} • ${escapeHtml(dev.osVersion || "v1.0")}</div>
            </div>
          </div>
          <div style="display: flex; align-items: center; gap: 8px;">
            ${isLocked 
              ? `<span class="kpi-badge badge-red">STOPPED</span>` 
              : `<span class="kpi-badge ${isOnline ? 'badge-green' : 'badge-yellow'}">${isOnline ? 'ONLINE' : 'SYNCING'}</span>`
            }
          </div>
        </div>

        <div class="device-keys-box">
          Device ID: ${dev.id}<br>
          Protection State: <strong style="color: ${isLocked ? '#f87171' : 'var(--accent-emerald)'}">${dev.protectionState || 'PROTECTED'}</strong>
        </div>

        <div class="device-footer">
          <span>Last Heartbeat: Live</span>
          <div style="display: flex; gap: 6px; align-items: center;">
            ${isLocked 
              ? `<button class="btn btn-outline-success btn-xs" onclick="window.dispatchDeviceCommand('${dev.id}', 'RESUME_APP')">
                  <svg style="width:12px;height:12px" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
                  Resume App
                </button>`
              : `<button class="btn btn-danger btn-xs" onclick="window.dispatchDeviceCommand('${dev.id}', 'STOP_APP')">
                  <svg style="width:12px;height:12px" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/></svg>
                  Stop App
                </button>`
            }
          </div>
        </div>
      </div>
    `;
  }).join("");
}

// ============================================================================
// POLICIES VIEW
// ============================================================================
async function fetchPolicies() {
  if (!state.token) return;
  try {
    const res = await fetch(`${API_BASE}/policies`, {
      headers: { "Authorization": `Bearer ${state.token}` }
    });
    if (res.ok) {
      state.policies = await res.json();
      renderPoliciesList();
    }
  } catch (e) {}
}

function renderPoliciesList() {
  const container = document.getElementById("policies-list-container");
  const tabBadge = document.getElementById("tab-policies-count");
  if (!container) return;

  const list = state.policies || [];
  if (tabBadge) tabBadge.innerText = list.length;

  if (list.length === 0) {
    container.innerHTML = `<p class="table-empty-row">No policies configured yet. Click "Add Policy" to restrict a domain.</p>`;
    return;
  }

  container.innerHTML = list.map(pol => {
    const targetVal = pol.targets && pol.targets[0] ? pol.targets[0].targetValue : "All Targets";
    const limitMins = pol.limitSeconds > 0 ? Math.round(pol.limitSeconds / 60) : 0;
    const isEnabled = pol.isEnabled !== false;

    return `
      <div class="policy-row-card">
        <div class="policy-info">
          <div class="policy-name-row">
            <span class="policy-title">${escapeHtml(pol.name)}</span>
            <span class="policy-target-chip">${escapeHtml(targetVal)}</span>
          </div>
          <div class="policy-meta">
            ${limitMins > 0 ? `Daily Cap: <strong>${limitMins} minutes</strong>` : `Strict 24/7 Block`}
            &bull; Action: <strong>${pol.enforcementMode || 'BLOCK'}</strong>
          </div>
        </div>

        <div class="policy-controls">
          <label class="switch" title="Toggle Policy">
            <input type="checkbox" ${isEnabled ? "checked" : ""} onchange="window.togglePolicy('${pol.id}')">
            <span class="slider"></span>
          </label>
          <button class="btn btn-sm btn-outline" style="color: #ef4444; border-color: rgba(239,68,68,0.25);" onclick="window.deletePolicy('${pol.id}')" title="Delete Policy">
            &times;
          </button>
        </div>
      </div>
    `;
  }).join("");
}

window.togglePolicy = async function(id) {
  try {
    const res = await fetch(`${API_BASE}/policies/${id}/toggle`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${state.token}` }
    });
    if (res.ok) {
      fetchPolicies();
      fetchWebsitesAnalytics();
      showToast("Policy state toggled", "info");
    }
  } catch (e) {}
};

window.deletePolicy = async function(id) {
  if (!confirm("Are you sure you want to remove this attention policy?")) return;
  try {
    const res = await fetch(`${API_BASE}/policies/${id}`, {
      method: "DELETE",
      headers: { "Authorization": `Bearer ${state.token}` }
    });
    if (res.ok) {
      fetchPolicies();
      fetchWebsitesAnalytics();
      showToast("Policy removed from all devices", "info");
    }
  } catch (e) {}
};

// ============================================================================
// POLICY SIMULATOR & QUICK RULES
// ============================================================================
window.inspectDomainPolicy = async function() {
  const domain = document.getElementById("inspect-domain-input").value.trim();
  if (!domain) return;

  try {
    const res = await fetch(`${API_BASE}/policies/explain`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${state.token}`
      },
      body: JSON.stringify({ target: domain })
    });

    if (res.ok) {
      const data = await res.json();
      document.getElementById("inspect-result-target").innerText = domain;
      const badge = document.getElementById("inspect-result-badge");
      const detail = document.getElementById("inspect-result-detail");
      const layers = document.getElementById("inspect-result-layers");

      if (data.allowed) {
        badge.className = "kpi-badge badge-green";
        badge.innerText = "PERMITTED";
        detail.innerText = data.reason || "Traffic allowed under current policy budget.";
      } else {
        badge.className = "kpi-badge badge-red";
        badge.innerText = "RESTRICTED / BLOCKED";
        detail.innerText = data.reason || "Domain access restricted by policy.";
      }

      layers.innerText = "BROWSER_EXTENSION (DNR) • MACOS_AGENT";
    }
  } catch (e) {
    showToast("Error inspecting policy", "alert");
  }
};

window.quickAddDomainRuleFor = function(domain) {
  document.getElementById("quick-domain-input").value = domain;
  switchTab("policies");
};

window.quickAddDomainRule = async function(minutes) {
  const domain = document.getElementById("quick-domain-input").value.trim();
  if (!domain) {
    showToast("Please enter a domain", "alert");
    return;
  }

  const name = minutes === 0 ? `Block ${domain}` : `${domain} (${minutes}m Cap)`;
  try {
    const res = await fetch(`${API_BASE}/policies`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${state.token}`
      },
      body: JSON.stringify({
        name: name,
        limitSeconds: minutes * 60,
        warningThresholdSeconds: minutes > 0 ? (minutes - 5) * 60 : 0,
        enforcementMode: "BLOCK",
        targets: [{ targetType: "DOMAIN", targetValue: domain }]
      })
    });

    if (res.ok) {
      document.getElementById("quick-domain-input").value = "";
      fetchPolicies();
      fetchWebsitesAnalytics();
      showToast(`Policy for '${domain}' created & applied everywhere!`, "success");
    }
  } catch (e) {
    showToast("Error creating policy", "alert");
  }
};

// ============================================================================
// AUDIT LOG
// ============================================================================
async function fetchAuditLogs() {
  if (!state.token) return;
  try {
    const res = await fetch(`${API_BASE}/audit/logs`, {
      headers: { "Authorization": `Bearer ${state.token}` }
    });
    if (res.ok) {
      state.auditLogs = await res.json();
      renderAuditLogs();
    }
  } catch (e) {}
}

function renderAuditLogs() {
  const container = document.getElementById("audit-list-container");
  if (!container) return;

  const list = state.auditLogs || [];
  if (list.length === 0) {
    container.innerHTML = `<p class="table-empty-row">No audit events recorded yet.</p>`;
    return;
  }

  container.innerHTML = list.slice(0, 20).map(log => {
    const t = log.timestamp ? new Date(log.timestamp).toLocaleTimeString() : "Just now";
    return `
      <div class="audit-item">
        <span class="audit-action-tag">${escapeHtml(log.action || "EVENT")}</span>
        <span class="audit-details">${escapeHtml(log.details || log.message || "")}</span>
        <span class="audit-time">${t}</span>
      </div>
    `;
  }).join("");
}

// ============================================================================
// MODALS
// ============================================================================
window.openPairingModal = async function() {
  const modal = document.getElementById("modal-pairing");
  if (modal) modal.style.display = "flex";
  await generateNewPairingCode();
};

window.closePairingModal = function() {
  const modal = document.getElementById("modal-pairing");
  if (modal) modal.style.display = "none";
  clearInterval(state.pairingTimerInterval);
};

window.generateNewPairingCode = async function() {
  try {
    const res = await fetch(`${API_BASE}/pairing/start`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${state.token}` }
    });

    if (res.ok) {
      const data = await res.json();
      const codeEl = document.getElementById("modal-pairing-code");
      if (codeEl) codeEl.innerText = data.pairingCode || "FG-2026";
      startPairingTimer(data.expiresInSeconds || 300);
    }
  } catch (e) {}
};

function startPairingTimer(seconds) {
  state.pairingSecondsLeft = seconds;
  const timerEl = document.getElementById("modal-pairing-timer");

  if (state.pairingTimerInterval) clearInterval(state.pairingTimerInterval);

  state.pairingTimerInterval = setInterval(() => {
    state.pairingSecondsLeft--;
    if (state.pairingSecondsLeft <= 0) {
      clearInterval(state.pairingTimerInterval);
      if (timerEl) timerEl.innerText = "Code expired. Click to refresh.";
      return;
    }
    const m = Math.floor(state.pairingSecondsLeft / 60);
    const s = state.pairingSecondsLeft % 60;
    if (timerEl) timerEl.innerText = `Expires in ${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  }, 1000);
}

window.openCreatePolicyModal = function() {
  const modal = document.getElementById("modal-create-policy");
  if (modal) modal.style.display = "flex";
};

window.closeCreatePolicyModal = function() {
  const modal = document.getElementById("modal-create-policy");
  if (modal) modal.style.display = "none";
};

window.submitCreatePolicy = async function() {
  const name = document.getElementById("new-policy-name").value.trim();
  const target = document.getElementById("new-policy-target").value.trim();
  const mins = parseInt(document.getElementById("new-policy-minutes").value, 10);
  const mode = document.getElementById("new-policy-mode").value;

  if (!name || !target) {
    showToast("Please enter a policy name and target domain", "alert");
    return;
  }

  try {
    const res = await fetch(`${API_BASE}/policies`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${state.token}`
      },
      body: JSON.stringify({
        name: name,
        limitSeconds: mins * 60,
        warningThresholdSeconds: mins > 0 ? (mins - 5) * 60 : 0,
        enforcementMode: mode,
        targets: [{ targetType: "DOMAIN", targetValue: target }]
      })
    });

    if (res.ok) {
      closeCreatePolicyModal();
      document.getElementById("new-policy-name").value = "";
      document.getElementById("new-policy-target").value = "";
      fetchPolicies();
      fetchWebsitesAnalytics();
      showToast(`Policy '${name}' created and synchronized!`, "success");
    }
  } catch (e) {
    showToast("Error creating policy", "alert");
  }
};

window.handleBackdropClick = function(e, modalId) {
  if (e.target && e.target.id === modalId) {
    document.getElementById(modalId).style.display = "none";
  }
};

// ============================================================================
// TAB SWITCHING
// ============================================================================
window.switchTab = function(tabName) {
  document.querySelectorAll(".view-tab").forEach(tab => {
    tab.classList.toggle("active", tab.id === `tab-${tabName}`);
    tab.setAttribute("aria-selected", tab.id === `tab-${tabName}`);
  });

  document.querySelectorAll(".tab-panel").forEach(panel => {
    panel.classList.toggle("active", panel.id === `panel-${tabName}`);
  });
};

// ============================================================================
// TOAST NOTIFICATIONS
// ============================================================================
function showToast(message, type = "info") {
  const container = document.getElementById("toast-container");
  if (!container) return;

  const toast = document.createElement("div");
  toast.className = `toast-item toast-${type}`;
  toast.innerHTML = `
    <span>${escapeHtml(message)}</span>
  `;

  container.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = "0";
    toast.style.transform = "translateY(10px)";
    toast.style.transition = "all 0.25s ease";
    setTimeout(() => toast.remove(), 250);
  }, 4000);
}

// Utility: HTML Escaping
function escapeHtml(text) {
  if (typeof text !== "string") return text;
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

// ============================================================================
// REMOTE DEVICE COMMAND DISPATCH (ADMIN LOCKDOWN & RESUME)
// ============================================================================
window.dispatchDeviceCommand = async function(deviceId, commandType) {
  if (!state.token) return;
  try {
    const isLock = commandType === "STOP_APP" || commandType === "LOCKDOWN_DEVICE";
    const actionText = isLock ? "Dispatching remote app shutdown..." : "Dispatching resume command...";
    showToast(actionText, "info");

    const res = await fetch(`${API_BASE}/commands/dispatch`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${state.token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        deviceId: deviceId,
        commandType: commandType,
        payload: {
          reason: isLock ? "Admin Emergency Stop" : "Admin Protection Resumed",
          initiatedBy: "admin_web_dashboard"
        }
      })
    });

    if (res.ok) {
      showToast(isLock ? "🛑 Device stopped and locked down successfully!" : "🔓 Device protection resumed!", "success");
      await fetchDevices();
    } else {
      const err = await res.json().catch(() => ({}));
      showToast(err.error || "Failed to dispatch command", "alert");
    }
  } catch (err) {
    showToast("Network error dispatching command", "alert");
  }
};

window.emergencyStopAllDevices = async function() {
  if (!confirm("🚨 Are you sure you want to trigger an EMERGENCY STOP on ALL paired devices? All target applications and distracting websites will be halted immediately.")) {
    return;
  }
  await window.dispatchDeviceCommand("ALL", "STOP_APP");
};

window.resumeAllDevices = async function() {
  await window.dispatchDeviceCommand("ALL", "RESUME_APP");
};
