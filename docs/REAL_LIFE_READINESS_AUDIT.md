# FocusGuard — Real-Life Readiness Audit & Reliability Blueprint

**Document Version**: `2.0.0-PROD-AUDIT`  
**Evaluation Standard**: Real-Life 30-Day Multi-Device Endurance (Windows, macOS, Android, Chrome, Firefox)  
**Priority Order**: `RELIABILITY > USABILITY > CORRECTNESS > PERFORMANCE > NEW FEATURES`

---

## 1. Executive Summary & Fleet Readiness Score

FocusGuard has built foundational cryptographic proofs and network interceptors (WebExtensions DNR/PSL, macOS Screen Time ManagedSettings, Android VpnService DNS sinkholes, and Go Chi/WebSocket cloud services). However, transitioning from an academic prototype to a daily-usable product requires surviving real-life anomalies: **laptop lid closure, midnight timezone crossings, VPN hops, WiFi/cellular toggles, browser kills, phone restarts, and server reboot storms.**

### Overall Readiness Scorecard

| Subsystem Category | Score (0–5) | State | Primary Limitation / Blocker |
|---|:---:|:---:|---|
| **1. INSTALLATION** | **2 / 5** | Partially Usable | Requires developer mode, terminal compilation; lacks single-click installers (`.dmg`, `.msi`, `.apk`). |
| **2. ONBOARDING** | **2 / 5** | Partially Usable | No progressive permission onboarding or step-by-step first-run wizard. |
| **3. AUTHENTICATION** | **3 / 5** | Usable | Backend has Argon2id/JWT, but web dashboard and extension hardcode demo credentials (`demo@focusguard.local`). |
| **4. PAIRING** | **3 / 5** | Usable | Pairing protocol and crypto pass 20 adversarial tests, but extension lacks pairing code entry UI. |
| **5. DEVICE RECOVERY** | **3 / 5** | Usable | Reconnection exists, but extension lacks automated token refresh / re-enrollment on revocation. |
| **6. POLICY SYNC** | **4 / 5** | **Reliable** | Monotonic versioning (`X-Policy-Version`) and atomic DNR rule compilation prevent stale overwrites. |
| **7. OFFLINE MODE** | **3 / 5** | Usable | Local SQLite/Room/SwiftData/Chrome storage works offline, but extension queue drain has a race condition. |
| **8. NETWORK RECOVERY** | **2 / 5** | Partially Usable | Extension uses naive `setTimeout(5000)` without jittered exponential backoff or network state machine. |
| **9. USAGE ACCURACY** | **2 / 5** | Partially Usable | `SyncUsage` lacks idempotency keys; network retries double-count usage totals. MV3 sleep jump deltas. |
| **10. ENFORCEMENT RELIABILITY** | **4 / 5** | **Reliable** | Defense-in-depth validated: DNR rules + local DNS NXDOMAIN sinkhole + Screen Time shields. |
| **11. BATTERY USAGE** | **3 / 5** | Usable | macOS and Windows agents poll at 1Hz fixed interval instead of event-driven OS window notifications. |
| **12. CPU USAGE** | **4 / 5** | **Reliable** | Go backend <0.5% CPU; extension negligible idle CPU; native agents <0.8% CPU. |
| **13. MEMORY USAGE** | **4 / 5** | **Reliable** | Bounded queues (500 events), SQLite WAL mode, and memory leaks contained under continuous load. |
| **14. BACKGROUND EXECUTION** | **2 / 5** | Partially Usable | Android manifest lacks `RECEIVE_BOOT_COMPLETED`; phone reboot leaves device unprotected. |
| **15. CRASH RECOVERY** | **3 / 5** | Usable | Focus session lacks timestamp-based elapsed calculation on restart; resets duration naively. |
| **16. DATA INTEGRITY** | **3 / 5** | Usable | SQLite transactions with foreign key cascades, but usage aggregates vulnerable to duplicate insertion. |
| **17. SECURITY** | **4 / 5** | **Reliable** | Argon2id, JWT HMAC-SHA256, Ed25519 pairing keypairs, rate limiters, 100% tenant isolation verified. |
| **18. PRIVACY** | **3 / 5** | Usable | Strict domain-only telemetry (no URLs/paths/cookies/queries), but lacks user-facing Privacy & Transparency UI. |
| **19. ERROR MESSAGES** | **3 / 5** | Usable | Block pages show reasons, but web UI silently catches fetch failures or prints cryptic console errors. |
| **20. UNINSTALL BEHAVIOR** | **3 / 5** | Usable | Manual removal works cleanly, but no documented self-service account/device data wipe workflow. |
| **21. UPDATES** | **3 / 5** | Usable | Backward-compatible API version headers exist, but no in-app update notification checks. |
| **22. OBSERVABILITY** | **3 / 5** | Usable | Structured logger and audit logs table exist; missing exportable sanitized support bundle (`support-report.json`). |

---

## 2. Detailed Subsystem Audit & Root Cause Analysis

### Subsystem 1: INSTALLATION (Score: 2 / 5)
- **Current State**: Extension must be loaded unpacked via Chrome Developer Mode (`chrome://extensions`). macOS requires `swift build`. Windows requires `dotnet build`. Android requires `./gradlew assembleDebug`.
- **Root Cause**: Build automation produces development binaries rather than consumer packages (`.crx`/`.xpi`, `.dmg`, `.msi`, `.apk`).
- **Implementation Task**: `FG-RL-101`: Build packaged artifacts and user-friendly step-by-step installation guides without developer tools.
- **Priority**: **P1**

### Subsystem 2: ONBOARDING & PERMISSION DISCLOSURE (Score: 2 / 5)
- **Current State**: When opened, dashboard immediately makes requests to `localhost:8080` without greeting the user or explaining device capabilities.
- **Root Cause**: Missing progressive permission onboarding flow explaining *What* is requested, *Why* it is needed, *What* FocusGuard does with it, and *What* happens if denied.
- **Implementation Task**: `FG-RL-102`: Design and implement progressive permission onboarding screen and first-time user wizard.
- **Priority**: **P1**

### Subsystem 3: AUTHENTICATION (Score: 3 / 5)
- **Current State**: Backend `/api/v1/auth/register` and `/api/v1/auth/login` are production-grade. However, `apps/web/app.js` and `apps/extension/background/service-worker.js` automatically authenticate as `demo@focusguard.local` with hardcoded password `focusguard123`.
- **Root Cause**: Prototype shortcut bypasses real user registration and login forms in the frontend.
- **Implementation Task**: `FG-RL-103`: Implement real user login, registration, logout, and token expiration recovery UI in web dashboard and extension.
- **Priority**: **P0**

### Subsystem 4: PAIRING & ENROLLMENT (Score: 3 / 5)
- **Current State**: Backend handles 6-character human-friendly codes with SHA-256 hashes and 5-minute expiry. `apps/device-test-client` pairs seamlessly. But `apps/extension` has a hardcoded static device ID (`00000000-0000-0000-0000-000000000002`) and no pairing screen in `popup.html`.
- **Root Cause**: Extension frontend was never wired to the pairing API.
- **Implementation Task**: `FG-RL-104`: Add device identity generation (UUIDv4) and pairing code entry modal to extension popup.
- **Priority**: **P0**

### Subsystem 5: DEVICE RECOVERY & TOKEN RENEWAL (Score: 3 / 5)
- **Current State**: If a JWT expires or device is revoked, backend returns HTTP 401/403. Extension does not re-authenticate or clear revoked credentials safely.
- **Root Cause**: Missing refresh token exchange loop in browser extension and desktop agents.
- **Implementation Task**: `FG-RL-105`: Implement automated refresh token renewal and clean credential eviction on revocation.
- **Priority**: **P1**

### Subsystem 7 & 8: OFFLINE MODE & NETWORK RECOVERY (Scores: 3 / 5 & 2 / 5)
- **Current State**:
  1. `drainOfflineQueue()` in `apps/extension/storage/policy-cache.js` completely clears `fg_offline_queue` upon a successful batch flush. If new events were enqueued while the HTTP request was in flight, they are permanently lost.
  2. WebSocket reconnection uses `setTimeout(connectWebSocket, 5000)`. In Manifest V3, the service worker goes dormant after 30s of inactivity, killing the timer. Reconnection lacks exponential backoff and jitter.
- **Root Cause**: Non-atomic queue drain and naive timer-based reconnection in an ephemeral service worker environment.
- **Implementation Task**: `FG-RL-106`: Implement atomic ID-based event queue drainage and an exponential backoff state machine (`ONLINE -> DEGRADED -> OFFLINE -> RECONNECTING -> SYNCING`).
- **Priority**: **P0**

### Subsystem 9 & 16: USAGE ACCURACY & DATA INTEGRITY (Scores: 2 / 5 & 3 / 5)
- **Current State**: In `backend/internal/usage/handler.go`:
  ```sql
  INSERT INTO usage_aggregates ...
  ON CONFLICT (user_id, device_id, target_value, date)
  DO UPDATE SET total_duration_seconds = usage_aggregates.total_duration_seconds + EXCLUDED.total_duration_seconds
  ```
  If a mobile or desktop client experiences a dropped connection or network retry, the identical usage delta is added multiple times, causing analytics to balloon erratically.
- **Root Cause**: Lack of idempotency keys or request deduplication tracking for usage synchronization deltas.
- **Implementation Task**: `FG-RL-107`: Implement idempotent usage delta tracking and request deduplication in Go backend and client sync adapters.
- **Priority**: **P0**

### Subsystem 14: BACKGROUND EXECUTION (Score: 2 / 5)
- **Current State**: Android `AndroidManifest.xml` does not declare `RECEIVE_BOOT_COMPLETED` permission and has no `BootReceiver`.
- **Root Cause**: Android OS terminates processes on reboot; without boot receiver, FocusGuard never restarts after a phone reboot.
- **Implementation Task**: `FG-RL-108`: Add `RECEIVE_BOOT_COMPLETED` permission and auto-start broadcast receiver on Android.
- **Priority**: **P0**

### Subsystem 15: CRASH RECOVERY & FOCUS SESSION RESILIENCE (Score: 3 / 5)
- **Current State**: If a computer reboots at minute 30 of a 90-minute focus session, the client restart either wipes the session or starts a fresh 90-minute timer.
- **Root Cause**: Countdown logic calculates remaining time from client RAM rather than `durationSeconds - (currentTime - startedAt)`.
- **Implementation Task**: `FG-RL-109`: Implement timestamp-based focus session elapsed calculation and recovery.
- **Priority**: **P0**

### Subsystem 18 & 22: PRIVACY & ADVANCED OBSERVABILITY (Score: 3 / 5)
- **Current State**: System collects only domains/bundle IDs, but users have no dedicated Privacy Dashboard or single-click Diagnostic Support Bundle generator.
- **Root Cause**: Diagnostic and privacy features are buried or unrendered in the web client.
- **Implementation Task**: `FG-RL-110`: Add Privacy & Data Transparency section, data export/deletion controls, and `support-report.json` diagnostic bundle generation.
- **Priority**: **P1**

---

## 3. Prioritized Engineering Backlog

### P0 — MUST FIX IMMEDIATELY (Blockers to 30-Day Daily Usability)
1. **`FG-P0-01`**: Usage Sync Idempotency & Deduplication Engine (`internal/usage/handler.go`).
2. **`FG-P0-02`**: Browser Extension Dynamic Device Identity, UUID Generation & Pairing UI (`apps/extension`).
3. **`FG-P0-03`**: Web Dashboard Real User Authentication (Sign Up, Sign In, Sign Out, Session Token persistence).
4. **`FG-P0-04`**: Extension Offline Queue Data Loss Fix (Atomic ID-based queue drainage).
5. **`FG-P0-05`**: Timestamp-Based Focus Session Recovery Across Restarts and Sleep.
6. **`FG-P0-06`**: Extension Network State Machine & Jittered Exponential Backoff Reconnection.
7. **`FG-P0-07`**: Android Boot Recovery (`RECEIVE_BOOT_COMPLETED` & Service Auto-Start).

### P1 — SHOULD FIX (Usability & Polish)
8. **`FG-P1-01`**: First-Time User Onboarding & Progressive Permission Wizard.
9. **`FG-P1-02`**: Privacy & Data Transparency UI (Data Export in CSV/JSON, Device & Data Deletion).
10. **`FG-P1-03`**: One-Click Diagnostic Support Bundle (`support-report.json`).
11. **`FG-P1-04`**: Fix Extension Dashboard link (`localhost:3001` vs `3000`).
12. **`FG-P1-05`**: macOS Event-Driven Foreground Application Notification (`NSWorkspace`).

### P2 — NICE TO HAVE (Post-Beta Enhancements)
13. **`FG-P2-01`**: Dark/Light mode theme customization.
14. **`FG-P2-02`**: Custom sounds on focus session completion.
15. **`FG-P2-03`**: Gamified attention streak milestones.
