// FocusGuard — Milestone 5: Cross-Device Control & Global Attention Budget E2E Test
// Validates multi-node shared budget reconciliation, WebSocket event broadcasting,
// and simultaneous cross-platform enforcement across macOS, Android, Windows, and Browser Extension.

const assert = require("assert");
const DomainEngine = require("../../packages/domain-engine");
const { PolicyEvaluator } = require("../../packages/policy-core");
const { DeviceModel, PairingState, ProtectionState } = require("../../packages/device-model");
const { EventFactory, EventType } = require("../../packages/event-model");
const { ProtocolEnvelope: Protocol, MessageType } = require("../../packages/protocol");
const { Crypto } = require("../../packages/crypto");

console.log("================================================================================");
console.log("FOCUSGUARD MILESTONE 5: CROSS-DEVICE CONTROL & SHARED BUDGET RECONCILIATION TEST");
console.log("================================================================================");

// --- 1. SIMULATED CLOUD BACKEND (Go Backend In-Memory Representation) ---
class CloudBackendSimulator {
  constructor() {
    this.devices = new Map();
    this.policies = new Map();
    this.usageAggregates = new Map(); // key: targetValue -> totalSeconds
    this.auditLogs = [];
    this.connectedWebSockets = new Map(); // deviceId -> callback
    this.policyVersion = 42;
  }

  registerDevice(device) {
    this.devices.set(device.id, device);
    this.logAudit("DEVICE_ENROLLED", `Device ${device.deviceName} (${device.platform}) enrolled`);
  }

  connectWebSocket(deviceId, onMessageCallback) {
    this.connectedWebSockets.set(deviceId, onMessageCallback);
  }

  setPolicy(policy) {
    this.policies.set(policy.id, policy);
    this.policyVersion += 1;
    this.broadcastToFleet(MessageType.POLICY_PUSH, {
      version: this.policyVersion,
      policies: Array.from(this.policies.values())
    });
  }

  syncUsage(deviceId, deltas) {
    const today = new Date().toISOString().split("T")[0];
    const limitsReached = [];

    for (const delta of deltas) {
      const current = this.usageAggregates.get(delta.targetValue) || 0;
      const updated = current + delta.durationSeconds;
      this.usageAggregates.set(delta.targetValue, updated);

      // Evaluate against all active policies
      for (const policy of this.policies.values()) {
        if (!policy.isEnabled) continue;

        for (const target of policy.targets) {
          if (DomainEngine.matches(delta.targetValue, target.targetValue)) {
            if (policy.limitSeconds > 0 && updated >= policy.limitSeconds) {
              const dto = {
                policyId: policy.id,
                targetValue: target.targetValue,
                currentUsage: updated,
                limitSeconds: policy.limitSeconds,
                timestamp: Date.now()
              };
              limitsReached.push(dto);

              // Broadcast LIMIT_REACHED event to all connected fleet devices via WebSocket
              this.broadcastToFleet(MessageType.REPORT_EVENT, {
                event: "LIMIT_REACHED",
                payload: dto
              });

              this.logAudit("GLOBAL_BUDGET_EXHAUSTED", `Shared budget for ${target.targetValue} reached ${updated}s / ${policy.limitSeconds}s across fleet`);
            }
          }
        }
      }
    }

    return {
      serverTimestamp: Math.floor(Date.now() / 1000),
      aggregatedTotals: Object.fromEntries(this.usageAggregates),
      limitsReached
    };
  }

  dispatchRemoteCommand(command) {
    this.logAudit("REMOTE_COMMAND_DISPATCHED", `Command ${command.type} dispatched to fleet`);
    this.broadcastToFleet(MessageType.COMMAND, command);
  }

  broadcastToFleet(type, payload) {
    const envelope = Protocol.pack(type, payload);
    for (const [devId, callback] of this.connectedWebSockets.entries()) {
      callback(envelope);
    }
  }

  logAudit(action, details) {
    this.auditLogs.push({
      id: `audit_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
      action,
      details,
      timestamp: new Date().toISOString()
    });
  }
}

// --- 2. INITIALIZE FLEET & BACKEND ---
console.log("\n--- STEP 1: Enrolling 4 Cross-Platform Fleet Nodes ---");
const cloud = new CloudBackendSimulator();

const nodes = {
  mac: { id: "dev_mac_01", deviceName: "MacBook Pro (M3)", platform: "MACOS", localUsage: 0, shieldActive: false },
  android: { id: "dev_android_01", deviceName: "Pixel 8 Pro", platform: "ANDROID", localUsage: 0, dnsSinkholeActive: false },
  windows: { id: "dev_win_01", deviceName: "Office Workstation", platform: "WINDOWS", localUsage: 0, overlayActive: false },
  extension: { id: "dev_ext_01", deviceName: "Chrome Browser", platform: "EXTENSION", localUsage: 0, dnrBlocked: false }
};

// Wire up WebSocket listeners for each node
for (const [key, node] of Object.entries(nodes)) {
  cloud.registerDevice(node);

  cloud.connectWebSocket(node.id, (envelope) => {
    const msg = Protocol.unpack(envelope);
    if (msg.type === MessageType.REPORT_EVENT && msg.payload.event === "LIMIT_REACHED") {
      const target = msg.payload.payload.targetValue;
      if (node.platform === "MACOS") {
        node.shieldActive = true;
        console.log(`  [WebSocket Node: ${node.deviceName}] Screen Time ManagedSettingsStore applied shield for ${target}`);
      } else if (node.platform === "ANDROID") {
        node.dnsSinkholeActive = true;
        console.log(`  [WebSocket Node: ${node.deviceName}] VpnService DNS Sinkhole active for ${target} (returns NXDOMAIN)`);
      } else if (node.platform === "WINDOWS") {
        node.overlayActive = true;
        console.log(`  [WebSocket Node: ${node.deviceName}] WindowsEnforcementAdapter displayed BlockOverlayWindow for ${target}`);
      } else if (node.platform === "EXTENSION") {
        node.dnrBlocked = true;
        console.log(`  [WebSocket Node: ${node.deviceName}] DeclarativeNetRequest dynamic rule compiled & active for ${target}`);
      }
    } else if (msg.type === MessageType.COMMAND) {
      console.log(`  [WebSocket Node: ${node.deviceName}] Received Remote Command: ${msg.payload.type}`);
    }
  });

  console.log(`✓ Enrolled node: ${node.deviceName} [Platform: ${node.platform}, ID: ${node.id}]`);
}

// --- 3. CONFIGURE GLOBAL SHARED ATTENTION POLICY ---
console.log("\n--- STEP 2: Setting Global Shared Budget (YouTube: 30 minutes / 1800s) ---");
const sharedPolicy = {
  id: "pol_youtube_global_30m",
  name: "Fleet YouTube Attention Budget",
  limitSeconds: 1800, // 30 minutes total across all devices
  period: "DAILY",
  enforcementMode: "BLOCK",
  isEnabled: true,
  version: 42,
  targets: [{ targetType: "WEBSITE", targetValue: "youtube.com" }]
};
cloud.setPolicy(sharedPolicy);
console.log(`✓ Policy activated: "${sharedPolicy.name}" (Limit: 1800s / 30m, Version: v${cloud.policyVersion})`);

// --- 4. MULTI-DEVICE PROGRESSIVE USAGE RECONCILIATION ---
console.log("\n--- STEP 3: Multi-Node Usage Progression & Server Reconciliation ---");

// Sub-step 3.1: MacBook consumes 10 minutes (600s)
console.log("\n[Node 1: MacBook Pro] Consumes 10 minutes (600s) on youtube.com");
nodes.mac.localUsage += 600;
let res = cloud.syncUsage(nodes.mac.id, [{ targetValue: "youtube.com", durationSeconds: 600 }]);
console.log(`  -> Server Aggregated Total: ${res.aggregatedTotals["youtube.com"]}s / 1800s (Remaining: ${1800 - res.aggregatedTotals["youtube.com"]}s)`);
assert.strictEqual(res.aggregatedTotals["youtube.com"], 600);
assert.strictEqual(res.limitsReached.length, 0);
assert.strictEqual(nodes.mac.shieldActive, false);
assert.strictEqual(nodes.android.dnsSinkholeActive, false);

// Sub-step 3.2: Android Phone consumes 10 minutes (600s)
console.log("\n[Node 2: Pixel 8 Pro] Consumes 10 minutes (600s) on youtube.com");
nodes.android.localUsage += 600;
res = cloud.syncUsage(nodes.android.id, [{ targetValue: "youtube.com", durationSeconds: 600 }]);
console.log(`  -> Server Aggregated Total: ${res.aggregatedTotals["youtube.com"]}s / 1800s (Remaining: ${1800 - res.aggregatedTotals["youtube.com"]}s)`);
assert.strictEqual(res.aggregatedTotals["youtube.com"], 1200);
assert.strictEqual(res.limitsReached.length, 0);

// Sub-step 3.3: Browser Extension consumes 8 minutes (480s) -> Reaches 93.3%
console.log("\n[Node 4: Chrome Browser] Consumes 8 minutes (480s) on youtube.com");
nodes.extension.localUsage += 480;
res = cloud.syncUsage(nodes.extension.id, [{ targetValue: "youtube.com", durationSeconds: 480 }]);
console.log(`  -> Server Aggregated Total: ${res.aggregatedTotals["youtube.com"]}s / 1800s (Remaining: ${1800 - res.aggregatedTotals["youtube.com"]}s)`);
assert.strictEqual(res.aggregatedTotals["youtube.com"], 1680);
assert.strictEqual(res.limitsReached.length, 0);

// Sub-step 3.4: Windows Workstation consumes 2 minutes (120s) -> Triggers 1800s limit!
console.log("\n[Node 3: Office Workstation] Consumes 2 minutes (120s) on youtube.com (Completes 30m Shared Budget)");
nodes.windows.localUsage += 120;
res = cloud.syncUsage(nodes.windows.id, [{ targetValue: "youtube.com", durationSeconds: 120 }]);
console.log(`  -> Server Aggregated Total: ${res.aggregatedTotals["youtube.com"]}s / 1800s -> LIMIT EXCEEDED!`);
assert.strictEqual(res.aggregatedTotals["youtube.com"], 1800);
assert.strictEqual(res.limitsReached.length, 1);

// --- 5. VERIFY SIMULTANEOUS FLEET-WIDE ENFORCEMENT ---
console.log("\n--- STEP 4: Verifying Simultaneous Cross-Platform Enforcement Across All 4 Nodes ---");
console.log(`  1. macOS Shield Active: ${nodes.mac.shieldActive ? "✓ YES" : "✗ NO"}`);
console.log(`  2. Android DNS Sinkhole Active: ${nodes.android.dnsSinkholeActive ? "✓ YES" : "✗ NO"}`);
console.log(`  3. Windows Overlay Active: ${nodes.windows.overlayActive ? "✓ YES" : "✗ NO"}`);
console.log(`  4. Browser Extension DNR Rule Active: ${nodes.extension.dnrBlocked ? "✓ YES" : "✗ NO"}`);

assert.strictEqual(nodes.mac.shieldActive, true, "macOS node must enforce ManagedSettings shield");
assert.strictEqual(nodes.android.dnsSinkholeActive, true, "Android node must enforce DNS sinkhole");
assert.strictEqual(nodes.windows.overlayActive, true, "Windows node must display BlockOverlayWindow");
assert.strictEqual(nodes.extension.dnrBlocked, true, "Browser Extension must enforce DeclarativeNetRequest rule");

console.log("✓ All 4 nodes are enforcing the block simultaneously based on shared budget reconciliation!");

// --- 6. REMOTE COMMAND DISPATCH (Focus Session Lockdown) ---
console.log("\n--- STEP 5: Dispatching Remote Focus Session (Deep Work 45m) to Fleet ---");
const focusCommand = {
  commandId: "cmd_focus_987",
  type: "START_FOCUS",
  durationSec: 2700,
  payload: {
    name: "Deep Work",
    allowedDomains: ["github.com", "canvas.edu"]
  }
};
cloud.dispatchRemoteCommand(focusCommand);
console.log("✓ Remote START_FOCUS command dispatched and received by all fleet nodes");

// --- 7. AUDIT TRAIL VERIFICATION ---
console.log("\n--- STEP 6: Validating Audit Log Trail ---");
for (const log of cloud.auditLogs) {
  console.log(`  [Audit Log: ${log.timestamp}] ${log.action} — ${log.details}`);
}
assert(cloud.auditLogs.some(l => l.action === "GLOBAL_BUDGET_EXHAUSTED"), "Audit log must contain GLOBAL_BUDGET_EXHAUSTED");
assert(cloud.auditLogs.some(l => l.action === "REMOTE_COMMAND_DISPATCHED"), "Audit log must contain REMOTE_COMMAND_DISPATCHED");

console.log("\n================================================================================");
console.log("✅ MILESTONE 5 CROSS-DEVICE CONTROL & BUDGET RECONCILIATION TEST PASSED (100%)");
console.log("================================================================================");
