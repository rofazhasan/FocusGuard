# FocusGuard Phase 2 Compatibility Audit for Phase 3 Windows Native Client

**Document ID**: FG-AUDIT-003  
**Date**: September 5, 2026  
**Status**: APPROVED BASELINE  
**Target Platform**: Windows 10 / 11 (x86_64, ARM64)  
**Client Type**: `WINDOWS_AGENT` (`apps/windows/`)

---

## 1. Executive Summary

This audit assesses the readiness of the FocusGuard Phase 2 backend, database schema, device authentication, pairing protocol, and WebSocket subsystems for seamless integration with the **Phase 3 Windows Native Client**. 

The goal of Phase 3 is to integrate directly with existing Phase 2 APIs without requiring breaking backend rewrites, ensuring continuous compatibility across the entire device fleet (Browser Extension, macOS Agent, Android Agent, and the new Windows Agent).

---

## 2. Compatibility Matrix of Phase 2 Endpoints

| Endpoint | Method | Auth Scope | Phase 2 Contract | Windows Native Client Use Case | Compatibility Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `/api/v1/pairing/sessions/:id/request` | `POST` | Public | Body: `{ deviceName, platform, clientType, appVersion, publicKey, keyAlgorithm }` | Device submits Ed25519 public key and metadata using scanned/pasted session ID | ✅ FULLY COMPATIBLE |
| `/api/v1/pairing/request` | `POST` | Public | Body: `{ pairingCode, deviceName, platform, clientType, appVersion, publicKey, keyAlgorithm }` | Device submits pairing request directly using 6-character human code `FG-XXXXXX` | ✅ FULLY COMPATIBLE |
| `/api/v1/pairing/sessions/:id/status` | `GET` | Public | Returns `{ status, deviceId, deviceToken, serverTime }`. Marks session `CONSUMED` | Device polls until status transitions `APPROVED`, extracts persistent `deviceToken` | ✅ FULLY COMPATIBLE |
| `/api/v1/devices/:id/heartbeat` | `POST` | `Bearer <deviceToken>` | Body: `{ appVersion, protectionState, policyVersion }`. Returns `{ acknowledged, status, latestPolicyVersion }` | Periodic health telemetry (default: every 60s) | ✅ FULLY COMPATIBLE |
| `/api/v1/device/policies/sync` | `GET` | `Bearer <deviceToken>` | Returns `{ policyVersion, policies, serverTime, syncCursor, status }` | Pulls assigned policies for local cache & enforcement | ✅ FULLY COMPATIBLE |
| `/api/v1/usage/sync` | `POST` | `Bearer <deviceToken>` | Body: `{ deviceId, syncSequence, usageDeltas }`. Returns `{ aggregatedTotal, limitsReached }` | Flushes aggregated daily process/app usage deltas | ✅ FULLY COMPATIBLE |
| `/api/v1/events/batch` | `POST` | `Bearer <deviceToken>` | Body: `{ events: [ { id, eventType, domain/target, reason, timestamp, metadata } ] }` | Flushes queued local events (`APP_SESSION_STARTED`, `LIMIT_REACHED`, `ENFORCEMENT_TRIGGERED`) | ✅ FULLY COMPATIBLE |
| `/ws` | `GET` (WSS) | `?token=<deviceToken>` | Realtime duplex WebSocket feed. Broadcasts `POLICY_UPDATED`, `LIMIT_REACHED`, `DEVICE_REVOKED` | Live policy updates and instantaneous zero-trust remote revocation | ✅ FULLY COMPATIBLE |
| `/api/v1/devices/:id/revoke` | `POST` | `Bearer <userToken>` | Marks device `REVOKED`, revokes credentials, broadcasts `DEVICE_REVOKED`, terminates WebSocket | Triggered by account owner on Dashboard | ✅ FULLY COMPATIBLE |

---

## 3. Detailed Subsystem Analysis

### 3.1 Device Identity & Cryptographic Material
- **Protocol**: Ed25519 keypair generated strictly on-device prior to enrollment.
- **Private Key Isolation**: The private key is retained exclusively on the local Windows machine under DPAPI / Windows Credential Manager and is never transmitted.
- **Server Registration**: The public key is submitted in PEM format via `POST /api/v1/pairing/sessions/:id/request`.

### 3.2 Device Token & Scoping
- **Token Claims**: `sub` (Device UUID), `device_id` (Device UUID), `user_id` (Owner UUID), `cred_version` (1), `role: "DEVICE"`.
- **Validation**: Backend `DeviceOrUserAuthMiddleware` confirms the device exists in `devices`, matches the tenant, and verifies `devices.status != 'REVOKED'`.
- **Security Invariant**: The Windows Client cannot invoke owner endpoints (`/api/v1/policies` CRUD, `/api/v1/devices/:id/revoke`), preserving strict least privilege.

### 3.3 Policy Schema Integration
- Policy targets in Phase 2 support `TargetType`: `"APP"`, `"WEBSITE"`, `"CATEGORY"`.
- The Windows client filters for `TargetType == "APP"` (or generic category policies where applicable) and matches `TargetValue` against canonical process names (e.g., `discord.exe`, `spotify.exe`, `steam.exe`).
- Monotonic versioning: The client tracks `latestPolicyVersion` and refuses stale policy downgrades.

### 3.4 Revocation Flow & Immediate Termination
When the owner revokes the Windows PC on the Dashboard:
1. Backend updates `devices.status = 'REVOKED'` and sets `device_credentials.revoked_at = NOW()`.
2. Realtime WebSocket Hub sends `{ "event": "DEVICE_REVOKED", "payload": { "deviceId": "...", ... } }` and severs the TCP connection.
3. Windows Client intercepts the WebSocket revocation message or receives `HTTP 403 Forbidden` (`code: "DEVICE_REVOKED"`) on any REST call.
4. Windows Client executes **Zero-Trust Revocation Routine**:
   - Invalidation of local DPAPI credential store.
   - Immediate cessation of outbound synchronization requests.
   - Transition of local state machine to `REVOKED`.
   - UI display of a persistent warning alerting the user that device access was terminated.

---

## 4. Platform-Specific Integration Requirements for Windows

1. **Secure Credential Storage**:
   - Windows Credential Manager / Data Protection API (`DPAPI` / `CryptProtectData`).
   - Cross-platform trait `SecureCredentialStorage` implemented via Win32 DPAPI on Windows and AES-GCM software store for CI/test mock environments.
2. **Foreground Process Detection**:
   - `GetForegroundWindow` $\to$ `GetWindowThreadProcessId` $\to$ `OpenProcess` with `PROCESS_QUERY_LIMITED_INFORMATION` $\to$ `QueryFullProcessImageNameW`.
3. **Idle Awareness**:
   - `GetLastInputInfo` to calculate system idle elapsed time (threshold: 60 seconds).
4. **Session Lock & Sleep Detection**:
   - Win32 session change notifications (`WTSRegisterSessionNotification`) or state interrogation to halt usage counting when the workstation is locked or suspended.
5. **Local Persistence**:
   - SQLite WAL database (`focusguard_client.db`) storing `device_state`, `cached_policies`, `usage_sessions`, `daily_usage`, `pending_events`, and `sync_state`.

---

## 5. Compatibility Risks & Mitigations

| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| Process name spoofing or collision (e.g. malicious binary named `discord.exe`) | Over-enforcement or bypass | Store and match full canonical executable paths (`C:\Users\...\Discord.exe`) where configured; default to verified process image inspection. |
| Critical Windows process targeted in policy | System instability or BSOD | Hardcoded protected process denylist (`System`, `csrss.exe`, `wininit.exe`, `winlogon.exe`, `services.exe`, `lsass.exe`, `smss.exe`, `explorer.exe`). Policy engine unconditionally rejects enforcement on denylisted targets. |
| Temporary network outages | Loss of tracking or crashes | Offline-first architecture: policies cached locally remain authoritative; usage deltas and events are queued in SQLite with exponential backoff sync. |
| Duplicate event ingestion | Inconsistent analytics | Idempotency keys (`evt_<uuid>`) on every event batch item. Backend ignores duplicates with HTTP 200 `{ processed, duplicates }`. |

---

## 6. Audit Conclusion

The FocusGuard Phase 2 architecture is 100% ready for Phase 3 Windows Native Client integration. No breaking changes or database migrations are required in the Go backend. All existing Phase 1 & 2 integration tests remain green.
