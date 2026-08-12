// FocusGuard Interactive Web Application Logic

// State Management
const state = {
  totalFocusMinutes: 137, // 2h 17m
  budgetUsedMinutes: 71,
  budgetTotalMinutes: 90,
  isFocusActive: false,
  selectedFocusMins: 45,
  focusRemainingSeconds: 2700, // 45m
  focusTimerInterval: null,
  
  // Simulator State
  macYoutubeMins: 17,
  androidYoutubeMins: 11,
  youtubeLimitMins: 30,

  topApps: [
    { name: "YouTube", category: "Video & Media", duration: "28m", color: "#ef4444" },
    { name: "Instagram", category: "Social Network", duration: "17m", color: "#a855f7" },
    { name: "Browser", category: "Web Research", duration: "41m", color: "#3b82f6" },
    { name: "Discord", category: "Messaging", duration: "12m", color: "#6366f1" }
  ],

  devices: [
    { name: "MacBook Pro 16\"", platform: "macOS 14.5", status: "Protected", lastSync: "20 sec ago", icon: "💻" },
    { name: "Pixel 8 Pro", platform: "Android 14", status: "Protected", lastSync: "1 min ago", icon: "📱" }
  ]
};

// DOM Elements
document.addEventListener("DOMContentLoaded", () => {
  renderAppList();
  renderDeviceList();
  setupEventListeners();
  updateSimulatorUI();
});

// Render Top Apps List
function renderAppList() {
  const container = document.getElementById("app-list-container");
  container.innerHTML = state.topApps.map(app => `
    <div class="app-item">
      <div class="app-info">
        <span class="app-dot" style="background-color: ${app.color}"></span>
        <div>
          <div class="app-name">${app.name}</div>
          <div class="text-small text-muted">${app.category}</div>
        </div>
      </div>
      <div class="app-time">${app.duration}</div>
    </div>
  `).join("");
}

// Render Devices List
function renderDeviceList() {
  const container = document.getElementById("device-list-container");
  container.innerHTML = state.devices.map(dev => `
    <div class="device-item">
      <div class="device-info">
        <span style="font-size: 18px;">${dev.icon}</span>
        <div>
          <div class="device-name">${dev.name}</div>
          <div class="text-small text-muted">Last sync: ${dev.lastSync}</div>
        </div>
      </div>
      <span class="device-status">${dev.status}</span>
    </div>
  `).join("");
}

// Setup Event Listeners
function setupEventListeners() {
  // Focus Session Duration Selector
  const durationBtns = document.querySelectorAll(".duration-btn");
  durationBtns.forEach(btn => {
    btn.addEventListener("click", () => {
      if (state.isFocusActive) return;
      durationBtns.forEach(b => b.classList.remove("active"));
      btn.classList.add("active");
      state.selectedFocusMins = parseInt(btn.dataset.mins, 10);
      state.focusRemainingSeconds = state.selectedFocusMins * 60;
      document.getElementById("focus-timer-display").innerText = formatSeconds(state.focusRemainingSeconds);
      document.getElementById("focus-btn-text").innerText = `START FOCUS (${state.selectedFocusMins}m)`;
    });
  });

  // Focus Toggle Button
  document.getElementById("btn-toggle-focus").addEventListener("click", toggleFocusSession);

  // Cross-Device Simulator Buttons
  document.getElementById("btn-sim-mac-add").addEventListener("click", () => {
    state.macYoutubeMins += 5;
    checkSimulatorLimit();
  });

  document.getElementById("btn-sim-android-add").addEventListener("click", () => {
    state.androidYoutubeMins += 5;
    checkSimulatorLimit();
  });

  // Modals
  document.getElementById("btn-new-policy").addEventListener("click", () => {
    document.getElementById("modal-policy").style.display = "flex";
  });

  document.getElementById("btn-close-policy-modal").addEventListener("click", () => {
    document.getElementById("modal-policy").style.display = "none";
  });

  document.getElementById("btn-cancel-policy").addEventListener("click", () => {
    document.getElementById("modal-policy").style.display = "none";
  });

  document.getElementById("btn-save-policy").addEventListener("click", () => {
    const name = document.getElementById("policy-name-input").value;
    const val = document.getElementById("policy-target-val").value;
    const mins = document.getElementById("policy-limit-input").value;

    state.topApps.unshift({
      name: name,
      category: val,
      duration: "0m",
      color: "#f59e0b"
    });
    renderAppList();

    document.getElementById("modal-policy").style.display = "none";
    alert(`Policy "${name}" applied! Target: ${val} (${mins} min/day budget).`);
  });

  // Blocker Screen Preview
  document.getElementById("btn-blocker-demo").addEventListener("click", () => {
    document.getElementById("modal-blocker").style.display = "flex";
  });

  document.getElementById("btn-close-blocker").addEventListener("click", () => {
    document.getElementById("modal-blocker").style.display = "none";
  });
}

// Toggle Focus Session
function toggleFocusSession() {
  const btn = document.getElementById("btn-toggle-focus");
  const btnText = document.getElementById("focus-btn-text");
  const statusBadge = document.getElementById("focus-status-badge");
  const timerDisplay = document.getElementById("focus-timer-display");
  const timerSubtext = document.getElementById("focus-timer-subtext");

  if (!state.isFocusActive) {
    // Start Focus
    state.isFocusActive = true;
    state.focusRemainingSeconds = state.selectedFocusMins * 60;
    btn.classList.add("active-focus");
    btnText.innerText = "END FOCUS SESSION";
    statusBadge.innerText = "ACTIVE";
    statusBadge.className = "badge badge-purple";
    timerSubtext.innerText = "ManagedSettings & VpnService shields active";

    state.focusTimerInterval = setInterval(() => {
      if (state.focusRemainingSeconds > 0) {
        state.focusRemainingSeconds--;
        timerDisplay.innerText = formatSeconds(state.focusRemainingSeconds);
      } else {
        toggleFocusSession();
      }
    }, 1000);
  } else {
    // End Focus
    clearInterval(state.focusTimerInterval);
    state.isFocusActive = false;
    btn.classList.remove("active-focus");
    btnText.innerText = `START FOCUS (${state.selectedFocusMins}m)`;
    statusBadge.innerText = "Ready";
    statusBadge.className = "badge badge-green";
    state.focusRemainingSeconds = state.selectedFocusMins * 60;
    timerDisplay.innerText = formatSeconds(state.focusRemainingSeconds);
    timerSubtext.innerText = "Click below to start instant lockout";
  }
}

// Check Simulator Limits
function checkSimulatorLimit() {
  const total = state.macYoutubeMins + state.androidYoutubeMins;
  document.getElementById("sim-mac-youtube-text").innerText = `YouTube: ${state.macYoutubeMins}m`;
  document.getElementById("sim-android-youtube-text").innerText = `YouTube: ${state.androidYoutubeMins}m`;
  document.getElementById("sim-cloud-total-text").innerText = `${total} / ${state.youtubeLimitMins} min`;

  const percent = Math.min(100, (total / state.youtubeLimitMins) * 100);
  document.getElementById("sim-progress-fill").style.width = `${percent}%`;

  if (total >= state.youtubeLimitMins) {
    document.getElementById("modal-blocker").style.display = "flex";
  }
}

function updateSimulatorUI() {
  checkSimulatorLimit();
}

function formatSeconds(sec) {
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}
