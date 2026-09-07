# FocusGuard Phase 2 & 3 Compatibility Audit for Phase 4 macOS Native Client

**Document ID**: FG-AUDIT-004  
**Version**: 1.0.0-PROD  
**Date**: September 7, 2026  
**Status**: APPROVED AUDIT BASELINE  
**Target Platform**: macOS 13.0+ (Ventura, Sonoma 14, Sequoia 15; Apple Silicon arm64 & Intel x86_64)  
**Client Target**: `MACOS_AGENT` (`apps/macos/`)

---

## 1. Executive Summary

This audit establishes the integration contracts, API compatibility baseline, security boundaries, and architectural differences between existing FocusGuard platforms (Phase 1 Browser Extension, Phase 2 Backend, Phase 3 Windows Native Client) and the **Phase 4 macOS Native Client**.

The goal of Phase 4 is to build a legitimate, production-grade native macOS application using SwiftUI and modern Swift concurrency that pairs into the existing FocusGuard ecosystem, respects macOS platform constraints (Transparency, Consent, and Control [TCC], App Sandbox, Hardened Runtime), integrates with existing backend REST and WebSocket contracts, and operates reliably offline.

---

## 2. Cross-Phase Compatibility Matrix

FocusGuard Phase 2 backend exposes REST endpoints (Go Chi) and WebSocket channels that Phase 4 macOS Native Client consumes directly:

| Endpoint | Method | Auth Scope | Phase 2 Contract | macOS Native Client Integration | Compatibility Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `/api/v1/pairing/request` | `POST` | Public | Body: `{ pairingCode, deviceName, platform, clientType, appVersion, publicKey, keyAlgorithm }` | Submits 6-char pairing code with Ed25519 identity key and macOS host metadata | ✅ FULLY COMPATIBLE |
| `/api/v1/pairing/sessions/{id}/request` | `POST` | Public | Body: `{ deviceName, platform, clientType, appVersion, publicKey, keyAlgorithm }` | QR / Session-based pairing request | ✅ FULLY COMPATIBLE |
| `/api/v1/pairing/sessions/{id}/status` | `GET` | Public | Polls until `APPROVED`, returns `deviceToken` and `deviceId` | Polling loop during onboarding | ✅ FULLY COMPATIBLE |
| `/api/v1/enrollment/claim` | `POST` | Public | Body: `{ pairingCode, deviceName, platform, osVersion }` | Legacy claim endpoint fallback | ✅ FULLY COMPATIBLE |
| `/api/v1/devices/{id}/heartbeat` | `POST` | `Bearer <deviceToken>` | Body: `{ appVersion, protectionState, policyVersion }` | Periodic health telemetry (default: 60s) | ✅ FULLY COMPATIBLE |
| `/api/v1/device/policies/sync` | `GET` | `Bearer <deviceToken>` | Returns `{ policyVersion, policies, serverTime, syncCursor, status }` | Pulls assigned policies for local SQLite cache | ✅ FULLY COMPATIBLE |
| `/api/v1/usage/sync` | `POST` | `Bearer <deviceToken>` | Body: `{ deviceId, syncSequence, usageDeltas }` | Flushes aggregated daily app usage deltas | ✅ FULLY COMPATIBLE |
| `/api/v1/events/batch` | `POST` | `Bearer <deviceToken>` | Body: `{ events: [ { id, eventType, domain/target, reason, timestamp, metadata } ] }` | Flushes queued local events (`USAGE_SESSION_STARTED`, `LIMIT_REACHED`, `ENFORCEMENT_TRIGGERED`) | ✅ FULLY COMPATIBLE |
| `/ws` | `GET` (WSS) | `?token=<deviceToken>` | Duplex WebSocket connection broadcasting `POLICY_UPDATED`, `DEVICE_REVOKED` | Live policy updates & immediate remote device revocation | ✅ FULLY COMPATIBLE |
| `/api/v1/devices/{id}/revoke` | `POST` | `Bearer <userToken>` | Marks device `REVOKED`, invalidates credentials, broadcasts `DEVICE_REVOKED` | Dashboard-initiated remote revocation | ✅ FULLY COMPATIBLE |

---

## 3. Subsystem Integration Analysis

### 3.1 Device Identity & Cryptography
- **Cryptographic Standard**: Ed25519 keypair generated on-device via Apple `CryptoKit` (`Curve25519.Signing.PrivateKey`).
- **Storage Isolation**: The private key and JWT `deviceToken` are stored exclusively in macOS **Keychain Services** using `kSecClassGenericPassword` with access flag `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Credentials are never written to unencrypted plist files or SQLite.
- **Client Metadata**: `platform: "MACOS"`, `clientType: "MACOS_AGENT"`, `osVersion: ProcessInfo.processInfo.operatingSystemVersionString`.

### 3.2 Application Identity Resolution: macOS vs. Windows
- On Windows (Phase 3), processes are identified primarily by executable image filename (`discord.exe`) or canonical path (`C:\...\Discord.exe`).
- On macOS (Phase 4), applications are identified primarily by **Bundle Identifier** (e.g. `com.hnc.Discord`, `com.spotify.client`, `com.apple.Safari`).
- **Normalization Policy**:
  - The macOS client normalizes `TargetValue` to lowercase bundle identifier.
  - For cross-platform policies specifying generic names (e.g. `discord`), a local domain normalizer maps known aliases (`discord` $\to$ `com.hnc.Discord`).
  - Window title matching is explicitly rejected as a primary identity provider to prevent spoofing.

### 3.3 Active Usage Detection & System Primitives
- **Foreground App Detection**: `NSWorkspace.shared.frontmostApplication` and `NSWorkspace.didActivateApplicationNotification`.
- **Idle State Detection**: `CGEventSourceSecondsSinceLastEventType(.combinedSessionState, .anyInputEventType)` determines idle duration without installing global keyloggers.
- **Lock / Sleep Detection**: Subscribes to `NSWorkspace.willSleepNotification`, `NSWorkspace.didWakeNotification`, and `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` distributed notifications via `DistributedNotificationCenter`.

### 3.4 Browser Coordination Boundary (Phase 1 vs. Phase 4)
- FocusGuard Phase 1 Browser Extension remains the authoritative enforcement component for URL/web policies within Google Chrome, Brave, and Edge.
- The macOS Native Client is responsible for application-level focus control, system-wide usage aggregation, device identity, and policy synchronization.
- Website enforcement is coordinated transparently; the native client does not perform DNS spoofing or kernel network filtering.

---

## 4. Platform-Specific Security & Safety Invariants

1. **Strict User Transparency**:
   - FocusGuard never operates in stealth mode.
   - The user must explicitly pair the application and approve notification/accessibility permissions.
   - A menu bar item and main window clearly reflect active tracking and policy state.
2. **Protected Application Denylist**:
   - Enforcement actions (such as warning overlays or application quit requests) strictly forbid targeting critical system applications:
     - `com.apple.finder` (Finder)
     - `com.apple.loginwindow` (loginwindow)
     - `com.apple.systempreferences` / `com.apple.systemsettings` (System Settings)
     - `com.apple.ActivityMonitor` (Activity Monitor)
     - `com.apple.dock` (Dock)
3. **No Private APIs / No SIP Bypass**:
   - Only public, documented Apple SDK frameworks are used (`AppKit`, `SwiftUI`, `CryptoKit`, `Security`, `SQLite3`, `UserNotifications`, `OSLog`).
   - No code injection, no dynamic library hijacking (`DYLD_INSERT_LIBRARIES`), no kernel extensions.

---

## 5. Potential Security Risks & Mitigations

| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| Clock tampering (user rolls back system wall time to extend limit) | Budget bypass | Timer engine uses `clock_gettime(CLOCK_MONOTONIC_RAW)` to measure actual elapsed duration independent of wall-clock changes. |
| Crash or sudden power loss during active usage session | Unbounded usage duration recorded | Short periodic checkpoints (every 5 seconds) committed to SQLite WAL. Crash recovery service resolves open sessions to the last valid checkpoint. |
| Offline tampering of local SQLite database | False usage / cleared limits | SQLite tables use versioning, checksum verification, and monotonic usage accumulation that rejects decrementing totals. |
| Remote device revocation delayed due to offline state | Revoked device continues syncing | On reconnect, the very first request validates credential validity with HTTP 403 / `code: "DEVICE_REVOKED"`, triggering immediate zero-trust wipe. |

---

## 6. Audit Conclusion

The FocusGuard Phase 2 backend architecture is 100% compatible with the Phase 4 macOS Native Client. All contracts are verified and ready for implementation.
