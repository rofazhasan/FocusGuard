# FocusGuard — Team Division, 8-Week Roadmap, Risk Register & MVP Definition

## 1. Two-Person Engineering Team Division

FocusGuard is built by a 2-person software engineering team. Responsibilities and subsystem ownership are strictly divided as follows:

### Developer A: Lead macOS Engineer & UI/UX Architect
- **Primary Domain**: macOS Native Application & FocusGuard Visual System
- **Core Technologies**: Swift 6, SwiftUI, FamilyControls, DeviceActivity, ManagedSettings, SwiftData, Keychain
- **Subsystems Owned**:
  - macOS Application Architecture (`apps/macos/FocusGuard`)
  - Apple Screen Time API Integrations (`FamilyControls`, `DeviceActivityMonitorExtension`, `ManagedSettingsStore`)
  - FocusGuard Design System (`FocusGuardTypography`, `FocusGuardColors`, `FocusGuardSpacing`)
  - Dashboard UI & Focus Mode Controls (`DashboardView`, `FocusSessionCard`, `PolicyEditor`)
  - macOS Client Security (`Keychain` token storage, monotonic uptime validator)

### Developer B: Lead Android & Backend Platform Engineer
- **Primary Domain**: Android Native Application & Go Micro-backend Infrastructure
- **Core Technologies**: Go 1.26, Chi, PostgreSQL 16, Gorilla WebSockets, Kotlin, Jetpack Compose, UsageStatsManager, VpnService, Room DB, WorkManager, Android Keystore
- **Subsystems Owned**:
  - Go Backend Micro-services (`backend/cmd/server`, `internal/`)
  - PostgreSQL Database DDL Migrations & Aggregation Queries (`backend/migrations/`)
  - Real-Time WebSocket Event Hub (`backend/internal/events`)
  - Android Application Architecture (`apps/android/app`)
  - Android Enforcement Subsystems (`UsageStatsManager`, `VpnService` Local DNS Sinkhole, `LockOverlayActivity`)
  - Android Background Synchronization (`WorkManager`, EncryptedSharedPreferences)

### Shared Responsibilities (Both Developers)
- Overall System Architecture & API Contract Alignment
- Monorepo Code Reviews & Pull Request Verification
- End-to-End Integration Testing & Cross-Device Limit Calculations
- Project Documentation & Final Evaluation Demo Preparation

---

## 2. 8-Week / 4-Sprint Implementation Roadmap

Each Sprint spans **2 Weeks** with clear deliverables and acceptance criteria.

```
+-------------------------------------------------------------------------------+
| SPRINT 1 (Weeks 1-2): Infrastructure, DB Schema, API Contracts & Backend Auth |
+-------------------------------------------------------------------------------+
  - FG-101: Monorepo folder setup & Docker Compose configuration.
  - FG-102: PostgreSQL DDL schema & migration scripts (000001_init_schema.up.sql).
  - FG-103: Complete OpenAPI 3.0 YAML specification & request schemas.
  - FG-201: Auth microservice (JWT access/refresh tokens, Argon2id/bcrypt hashing).
  - FG-202: Device management service (Register, List, Heartbeat).
  - FG-203: Policy CRUD service with versioning and target mapping.

+-------------------------------------------------------------------------------+
| SPRINT 2 (Weeks 3-4): macOS & Android Platform Core Shells                    |
+-------------------------------------------------------------------------------+
  - FG-301: macOS SwiftUI architecture setup & SwiftData local entities.
  - FG-302: macOS FamilyControls authorization workflow & status handler.
  - FG-303: macOS DeviceActivityMonitor out-of-process threshold callback handler.
  - FG-401: Android Jetpack Compose architecture & Room DB implementation.
  - FG-402: Android UsageStatsManager foreground tracking worker.

+-------------------------------------------------------------------------------+
| SPRINT 3 (Weeks 5-6): Network Enforcement, WebSockets & Cross-Device Engine  |
+-------------------------------------------------------------------------------+
  - FG-304: macOS ManagedSettings custom ShieldConfiguration extensions.
  - FG-403: Android VpnService local DNS sinkhole for website blocking.
  - FG-404: Android full-screen lock overlay for application enforcement.
  - FG-501: Go Gorilla WebSocket broadcast hub and connection registry.
  - FG-502: macOS WebSocket client with automatic reconnection & offline queue.
  - FG-503: Android WorkManager synchronization worker.
  - FG-504: Server-side cross-device usage aggregator & limit calculator.

+-------------------------------------------------------------------------------+
| SPRINT 4 (Weeks 7-8): Focus Mode, Security Anti-Tamper & E2E Testing          |
+-------------------------------------------------------------------------------+
  - FG-601: Focus Session countdown engine (macOS & Android).
  - FG-602: Backend analytics SQL aggregation for top distraction metrics.
  - FG-603: Native UI Analytics Dashboards & Charts.
  - FG-701: Monotonic clock validator & time-tamper detection engine.
  - FG-702: Secure Token Storage (Apple Keychain & Android KeyStore TEE).
  - FG-801: Go API integration test suite.
  - FG-802: macOS XCTest unit suite for policy engine.
  - FG-803: Android JUnit/Espresso unit test suite.
```

---

## 3. Risk Register & OS Boundary Mitigations

| Risk ID | Risk Title | Severity | Impact | Mitigation Strategy |
|---|---|---|---|---|
| **RSK-01** | `FamilyControls` Authorization Denied | High | macOS app cannot shield apps/web | Onboarding step clearly explains Apple Screen Time privacy protections. App falls back to notification alerts and diagnostic status UI. |
| **RSK-02** | Local System Clock Manipulation | Critical | Bypasses time limits | Use hardware monotonic clocks (`CLOCK_MONOTONIC_RAW` / `SystemClock.elapsedRealtime()`). Compare local wall clock with `X-Server-Timestamp` and lock app if drift > 120s. |
| **RSK-03** | Android Background Process Termination | Medium | Delayed usage tracking or sync | Register `VpnService` as a Foreground Service with an ongoing notification. Use `WorkManager` with `NetworkType.CONNECTED` constraints. |
| **RSK-04** | Offline Reconnection Double-Counting | High | Distorted usage metrics | Telemetry events contain client-generated UUIDs and monotonic start/end timestamps. Backend performs idempotent `ON CONFLICT` aggregation. |
| **RSK-05** | Google Play Policy Compliance for VPN | Medium | App rejection | VPN processes DNS traffic 100% locally on-device without remote proxying or data exfiltration, strictly complying with Google Play VpnService policies. |

---

## 4. MVP Definition vs Post-MVP Scope

### MVP Scope (CSE 3200 Evaluation Requirements):
1. **Real Native Usage Detection**:
   - macOS: Apple `DeviceActivity` framework monitoring.
   - Android: Android `UsageStatsManager` foreground app tracking.
2. **Real OS-Level Enforcement**:
   - macOS: `ManagedSettingsStore` shielding applications and web domains.
   - Android: `VpnService` local DNS sinkhole for websites + full-screen lock overlay for apps.
3. **Local-First Policy Engine**:
   - Cached local database persistence (SwiftData / Room DB) for offline operation.
4. **Cross-Device Telemetry Synchronization**:
   - Go backend microservice with PostgreSQL database.
   - Gorilla WebSockets real-time sync for combined cross-device budget exhaustion (`LIMIT_REACHED`).
5. **Anti-Tamper Security**:
   - Monotonic hardware clock drift detection.
   - Secure Keychain / KeyStore TEE token storage.
6. **Focus Mode Sessions**:
   - On-demand 15m, 30m, 45m focus sessions with strict temporary shields.
7. **Premium UI/UX System**:
   - Calm, dark-mode native UI built with SwiftUI and Jetpack Compose using traceable real data.

### Post-MVP Scope (Future Iterations):
- Machine Learning models for automatic distraction categorization.
- Multi-user Family / Team organization administration portal.
- Browser Extension sub-path URL tracker for deep web analytics.
