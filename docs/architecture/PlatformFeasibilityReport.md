# FOCUSGUARD — Platform Feasibility & Engineering Architecture Specification

**Project**: FocusGuard ("Protect your attention, automatically.")  
**Course**: CSE 3200 Software Development  
**Target Platforms**: macOS (Native Swift/SwiftUI), Android (Kotlin/Compose), Backend (Go + PostgreSQL/SQLite)

---

## 1. Executive Feasibility Analysis

FocusGuard requires real-time attention monitoring and strict enforcement across macOS and Android without utilizing dangerous kernel exploits, stealth daemons, or OS security bypasses.

```
REAL USAGE
     ↓
USAGE AGGREGATION
     ↓
POLICY ENGINE
     ↓
LIMIT REACHED
     ↓
REAL OS / NETWORK ENFORCEMENT
     ↓
BLOCK EVENT & AUDIT
     ↓
REAL-TIME WEBSOCKET BROADCAST
     ↓
EXECUTIVE ANALYTICS
```

### Platform Feasibility Matrix

| Platform | Monitoring Capability | Strongest Official Enforcement Mechanism | Fallback / Degradation Mode |
|---|---|---|---|
| **macOS (13.0+)** | `DeviceActivityReport` & `NSWorkspace` / Accessibility active app tracking | `ManagedSettings.ManagedSettingsStore` application & webDomain shields | Application termination / notification warning if Screen Time authorization revoked |
| **Android (API 26+)** | `UsageStatsManager.queryEvents()` foreground app detection | `VpnService` local DNS sinkhole (NXDOMAIN) + Full-screen System Alert Window lockout | Notification alert + persistent foreground warning if overlay permission missing |
| **Backend / Cloud** | Ingestion via REST (`POST /api/v1/usage/sync`) | Real-time WebSocket broadcasting (`LIMIT_REACHED`, `POLICY_UPDATED`) | Offline delta queue with replay and idempotent server versioning |

---

## 2. Technical Proofs Design

### PROOF A: macOS Native Enforcement Proof
1. **Usage Monitoring**: Monitor frontmost application and active domains.
2. **Threshold Trigger**: When cumulative usage >= policy limit (e.g. 30 seconds for test proof, 30 minutes for production).
3. **Enforcement Execution**: Invokes `ManagedSettingsStore.shield.applications` and `ManagedSettingsStore.shield.webDomains` to trigger native Apple Screen Time shields.

### PROOF B: Android VpnService DNS Sinkhole Proof
1. **Usage Session Tracking**: Track foreground app transition via `UsageEvents.Event.ACTIVITY_RESUMED` and `ACTIVITY_PAUSED`.
2. **Local Policy Decision**: `AndroidPolicyEvaluator.isLimitExceeded()`.
3. **Network Enforcement**: `FocusVpnService` routes DNS queries to local TUN interface. If query matches blocked domain (e.g. `youtube.com`, `instagram.com`), returns `NXDOMAIN` (RCODE 3), actively blocking network transport.

---

## 3. Data Integrity & Idempotency Rules

- **UUIDv4 Identity**: Every device, user, policy, and usage session is uniquely identified with a UUID.
- **Deduplication**: `usage_aggregates` table enforces unique constraint `UNIQUE(user_id, device_id, target_value, date)`.
- **Session Splitting**: Overlapping sessions are merged using interval unions; sessions crossing midnight (00:00 UTC) are split into two discrete day records to prevent cross-day pollution.
- **Monotonic Clock Guard**: `CLOCK_MONOTONIC_RAW` (macOS) and `SystemClock.elapsedRealtime()` (Android) are compared against wall-clock time (`gettimeofday()`) to detect clock tampering attempts.
