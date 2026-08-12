# FocusGuard — Two-Person Sprint Coordinator Plan

This document establishes the official 2-person sprint coordination matrix, ownership division, parallelized workflow, daily standup protocol, integration day schedules, and deadline protection rules for FocusGuard.

---

## 1. Developer Ownership Matrix

```
+-----------------------------------------------------------------------------------+
| DEVELOPER A (Lead macOS & UI/UX Architect)                                         |
+-----------------------------------------------------------------------------------+
| Primary Modules:                                                                  |
|   - apps/macos/ (Swift 6, SwiftUI, SwiftData, Keychain)                           |
|   - Platform Screen Time: FamilyControls, DeviceActivity, ManagedSettings          |
|   - ShieldConfigurationExtension custom UI                                         |
|   - FocusGuard Visual System: Tokens, Typography, Palette, Radius, Spacing         |
|   - macOS UI: DashboardView, HeaderGreeting, AttentionBudgetHeroCard, AppCardRow,  |
|     FocusSessionCard, DeviceCardGrid, PolicyEditorView, BlockScreenView, StateViews |
|   - macOS Client Monotonic Clock Validator (CLOCK_MONOTONIC_RAW)                  |
+-----------------------------------------------------------------------------------+

+-----------------------------------------------------------------------------------+
| DEVELOPER B (Lead Android & Backend Platform Engineer)                            |
+-----------------------------------------------------------------------------------+
| Primary Modules:                                                                  |
|   - backend/ (Go 1.26, Chi REST API, PostgreSQL 16 DDL, Gorilla WebSockets Hub)    |
|   - apps/android/ (Kotlin, Jetpack Compose, Room DB, WorkManager, KeyStore)        |
|   - Android Subsystem: UsageStatsManager, VpnService Local DNS Sinkhole, Overlay   |
|   - Backend Services: Auth (JWT/Argon2id), Devices, Policies, Usage Sync          |
|   - Backend Analytics (GET /analytics/daily, GET /analytics/weekly)               |
|   - Android UI: DashboardScreen, FocusGuardTheme, AttentionBudgetRingCard          |
+-----------------------------------------------------------------------------------+

+-----------------------------------------------------------------------------------+
| SHARED RESPONSIBILITIES (Developer A + Developer B)                               |
+-----------------------------------------------------------------------------------+
| Shared Modules & Processes:                                                       |
|   - System Architecture Specification (docs/architecture/Architecture.md)         |
|   - OpenAPI 3.0 Contract & WebSocket Protocol (packages/api-contracts/openapi.yaml) |
|   - Peer Code Reviews (PR verification across repos)                              |
|   - Cross-Device Integration Testing (macOS + Android combined budget sync)       |
|   - End-to-End Demo Verification                                                  |
+-----------------------------------------------------------------------------------+
```

---

## 2. 4-Sprint Parallelized Task Assignment

```
SPRINT 1 (Weeks 1-2): Foundation, Infrastructure, DB Schema & Core API
---------------------------------------------------------------------
Developer A:
  - FG-301: macOS SwiftUI architecture shell & SwiftData entity setup (3d)
  - FG-302: FamilyControls authorization request workflow (2d)
Developer B:
  - FG-101: Monorepo layout & Docker Compose PostgreSQL setup (2d)
  - FG-102: PostgreSQL migration DDL scripts (000001_init_schema.up.sql) (2d)
  - FG-103: OpenAPI 3.0 YAML specification (2d)
  - FG-201: Go JWT Auth microservice (Argon2id/bcrypt) (2d)
Integration Day (Sprint 1 End):
  - Developer A + B verify Docker server boot and initial macOS auth connection.

SPRINT 2 (Weeks 3-4): Platform Engine Shells & Local Policy Enforcement
----------------------------------------------------------------------
Developer A:
  - FG-303: macOS DeviceActivityMonitor out-of-process threshold handler (3d)
  - FG-304: ManagedSettings custom ShieldConfigurationExtension UI (2d)
Developer B:
  - FG-202: Device management REST endpoints (2d)
  - FG-203: Policy CRUD service with versioning (2d)
  - FG-401: Android Jetpack Compose architecture & Room DB (3d)
  - FG-402: Android UsageStatsManager tracking service (2d)
Integration Day (Sprint 2 End):
  - Developer A + B verify policy creation API and local shield activation on both platforms.

SPRINT 3 (Weeks 5-6): Network Enforcement, Real-Time WebSockets & Cross-Device Engine
-------------------------------------------------------------------------------------
Developer A:
  - FG-502: macOS WebSocket client & offline delta sync queue (3d)
  - FG-601a: macOS Focus Session countdown UI & timer (2d)
Developer B:
  - FG-403: Android VpnService local DNS sinkhole for website blocking (3d)
  - FG-404: Android full-screen lock overlay UI (2d)
  - FG-501: Go WebSocket broadcast hub (2d)
  - FG-503: Android WorkManager sync worker (2d)
  - FG-504: Server-side cross-device usage limit calculator (2d)
Integration Day (Sprint 3 End):
  - Developer A + B test multi-device usage aggregation: 15m Mac + 15m Android = LIMIT_REACHED event broadcast.

SPRINT 4 (Weeks 7-8): Security Anti-Tamper, Visual Transformation & E2E Verification
-------------------------------------------------------------------------------------
Developer A:
  - FG-701a: macOS CLOCK_MONOTONIC_RAW anti-tamper drift validator (2d)
  - FG-603a: macOS Design System tokens, Hero Ring Card & Dashboard polish (3d)
  - FG-802: macOS XCTest policy engine test suite (2d)
Developer B:
  - FG-602: Backend Analytics queries (GET /analytics/daily & /weekly) (2d)
  - FG-603b: Android Compose design system polish & canvas ring (2d)
  - FG-701b: Android SystemClock.elapsedRealtime() drift validator (1d)
  - FG-702: Keychain & KeyStore TEE token storage (2d)
  - FG-801: Go API integration test suite (2d)
  - FG-803: Android JUnit test suite (2d)
Integration Day (Sprint 4 End):
  - Developer A + B run full regression test suite (`go test ./...`, `swiftc -parse`, `JUnit`) and final demo walkthrough.
```

---

## 3. Daily Collaboration Standup Protocol

Every morning, each developer logs:

```text
[DAILY STANDUP REPORT]
Developer: Developer A / Developer B
Yesterday: Completed FG-304 ManagedSettings custom shield UI and verified syntax.
Today: Implementing FG-502 macOS WebSocket client & offline queue.
Blocked: None.
Risk: None.
```

---

## 4. Peer Code Review & Integration Protocol

1. **Pull Request Protocol**:
   - Every feature branch (`feature/FG-xxx-...`) requires a PR targeting `develop`.
   - PR must be reviewed and approved by the *other* developer before merging.
2. **Integration Day Protocol**:
   - Scheduled on Friday at the end of each Sprint.
   - Both developers checkout `develop`, start local backend Docker database, launch macOS app and Android app, and verify full end-to-end user flows.

---

## 5. Deadline Protection & MVP Shield Rule

If any task threatens the 8-week delivery deadline, it is immediately demoted to **STRETCH**. The core MVP components are protected unconditionally:

1. Real native usage monitoring (`DeviceActivity` / `UsageStatsManager`)
2. Real native enforcement (`ManagedSettingsStore` / `VpnService` DNS sinkhole)
3. Local Policy Engine
4. Cross-device synchronization engine
5. Offline delta resilience
6. Verified automated test suites
7. Final demo walkthrough
