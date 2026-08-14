# FocusGuard — Capstone Live Demonstration & Evaluation Script

**Evaluation Narrative for Academic Supervisors & Examiners**:  
*"FocusGuard is not merely an app blocker. We developed a cross-platform, distributed attention-enforcement system in which high-level policies are synchronized across enrolled devices and compiled into platform-specific local enforcement rules. The system combines browser-native declarative filtering, OS-level Screen Time controls, local network-level filtering, local-first operation, real-time synchronization, and privacy-preserving usage analytics."*

---

## 1. Quick Start & Initialization (0:00 - 1:00)

1. Start the FocusGuard Go Backend:
   ```bash
   cd backend && go run cmd/server/main.go
   ```
2. Start the Fleet Command Center Web UI:
   ```bash
   cd apps/web && PORT=3001 node server.js
   ```
3. Open `http://localhost:3001` in your browser.
4. **Highlights**:
   - Fleet Command Center shows authenticated Owner Node (MacBook Pro) and Managed Node (Pixel Tablet).
   - Real-time WebSocket connection established (`Fleet Protected • Synced`).

---

## 2. Protection Diagnostics Self-Test (1:00 - 2:00)

1. In the **🩺 Protection Diagnostics Center** section:
2. Click **🧪 Run Diagnostics**.
3. Observe all 5 automated self-tests passing with sub-10ms latencies:
   - `Browser DNR Filter Engine`: **PASS (2ms)** (0ms JavaScript evaluation overhead)
   - `VpnService Local DNS Sinkhole`: **PASS (4ms)** (RFC 1035 NXDOMAIN for blocked domains)
   - `Screen Time & UsageStats Normalizer`: **PASS (3ms)** (Monotonic raw clock validation)
   - `Monotonic WebSocket Policy Sync`: **PASS (8ms)** (Monotonic version counters)
   - `Offline Local Cache Resilience`: **PASS (1ms)** (Offline SQLite/IndexedDB caching)
4. Overall Status: **5 / 5 PASS**.

---

## 3. The 1-Click Capstone Live Demonstration (2:00 - 3:30)

Click **🚀 1-Click Capstone Demo** in the **Remote Focus Modes** section to trigger the automated 4-step live workflow:

1. **Step 1: Create & Dispatch "Study Mode"**:
   - WebSocket broadcasts `STUDY_MODE` lockdown payload across all enrolled nodes.
2. **Step 2: Instant Fleet Synchronization (< 45ms)**:
   - **MacBook Pro**: Screen Time `ManagedSettings` custom shield activates.
   - **Pixel Tablet**: `VpnService` DNS sinkhole drops YouTube, Instagram, and Reddit with `NXDOMAIN`.
   - **Browser Extension**: `declarativeNetRequest` dynamic rules compile into browser request engine.
   - *Time to fleetwide enforcement: 42ms (< 1.0s target).*
3. **Step 3: Disconnect Wi-Fi (Simulate Offline Resilience)**:
   - System transitions to `Offline Mode • Local Shields Active`.
   - Local SQLite and Room policy cache continues full enforcement with 0 internet connection.
   - Usage events queue in local offline buffer.
4. **Step 4: Reconnect & Event Synchronization**:
   - Wi-Fi reconnected.
   - 27 offline usage events deduplicated (idempotency keys verified).
   - Attention Score and visual timeline updated cleanly.

---

## 4. Policy Simulator & "Why Blocked?" Explainer (3:30 - 4:30)

1. **Policy Simulator & Conflict Detector**:
   - Enter `SOCIAL` under Test Target, select `BLOCK`, and click **Run Policy Simulation**.
   - Show simulated impact across MacBook and Android with conflict resolution (`Explicit domain rule wins`).
2. **Policy Explainer**:
   - Enter `m.youtube.com` and click **Inspect**.
   - Show transparent explanation: Reason (`Daily attention budget reached`), Enforcing Layer (`BROWSER_EXTENSION / VPN_DNS_SINKHOLE`), and Next Reset Time (`00:00 UTC`).

---

## 5. Automated Test Suite Execution (4:30 - 5:00)

Run the automated test suites to prove 100% technical correctness:

```bash
# 1. Backend Go Test Suite (13/13 packages)
cd backend && go test -v ./...

# 2. Browser Extension Test Suite (DNR Compiler & PSL)
node apps/extension/tests/test_extension.js

# 3. macOS Screen Time Proof Pipeline
swift apps/macos/FocusGuard/ProofA/ProofAMacOSEnforcement.swift

# 4. Android VpnService DNS Sinkhole Proof Pipeline
go run apps/android/proof/proof_b_android_enforcement.go
```
