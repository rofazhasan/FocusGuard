# FocusGuard Phase 4 macOS Native Client Architecture Specification

**Document ID**: FG-ARCH-004  
**Version**: 4.0.0-PROD  
**Date**: September 7, 2026  
**Status**: APPROVED ARCHITECTURE  
**Target Platform**: macOS 13.0+ (Ventura, Sonoma 14, Sequoia 15; arm64 & x86_64)  
**Implementation**: Native Swift & SwiftUI (`apps/macos/FocusGuard/`)

---

## 1. System Architecture Overview

The FocusGuard macOS Native Client uses a clean-architecture layered model that isolates platform-specific macOS system APIs (`AppKit`, `NSWorkspace`, `Keychain`, `SQLite`) from domain rules (pure deterministic policy evaluation, monotonic time tracking, usage state machines, and event queuing).

```
┌────────────────────────────────────────────────────────────────────────┐
│                              SWIFTUI APP                               │
│                                                                        │
│  [ Dashboard ]   [ Applications ]   [ Usage ]   [ Policies ]           │
│  [ Devices ]     [ Settings ]       [ Diagnostics ]                    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                               ViewModels / ObservableObject
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                          APPLICATION LAYER                             │
│                                                                        │
│  DeviceService        PolicyService        UsageService                │
│  TimerService         EnforcementService   SyncService                 │
│  RealtimeService      CrashRecoveryService                             │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                             DOMAIN LAYER                               │
│                                                                        │
│  DeviceIdentity       Policy & Target      UsageSession & State        │
│  UsageStateMachine    PolicyEngine         EnforcementDecision         │
│  EventEnvelopes       ProtectedAppSafety   MonotonicClockGuard         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                            INFRASTRUCTURE                              │
│                                                                        │
│  NSWorkspace          Accessibility APIs   Keychain Storage            │
│  SQLite WAL Store     URLSession REST      WebSocket Hub               │
│  UserNotifications    OSLog Subsystem      DistributedNotification     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
             ┌──────────────────────┴──────────────────────┐
             ▼                                             ▼
┌─────────────────────────┐                   ┌─────────────────────────┐
             │       macOS SYSTEM      │                   │   FOCUSGUARD BACKEND    │
│  NSWorkspace Frontmost  │                   │  HTTPS REST API (v1)    │
│  CGEventSource Idle     │                   │  WSS Realtime Hub       │
│  DistributedNotif Lock  │                   │  Policy & Event Sync    │
│  Keychain Services      │                   │  Device Revocation      │
└─────────────────────────┘                   └─────────────────────────┘
```

---

## 2. Directory & Component Structure

The client codebase is housed in `apps/macos/` adhering to strict domain-driven hexagonal boundaries:

```
apps/macos/
├── Package.swift                      # Swift Package Manager manifest
├── FocusGuard/
│   ├── App/
│   │   ├── FocusGuardApp.swift        # Main SwiftUI application entry point
│   │   ├── AppState.swift             # Global observable application state
│   │   └── DependencyContainer.swift  # Dependency injection & service factory
│   │
│   ├── Presentation/                  # SwiftUI UI & ViewModels
│   │   ├── Navigation/                # Sidebar & split-view navigation
│   │   ├── Dashboard/                 # Attention hero card & live summary
│   │   ├── Applications/              # Discovered applications & track toggles
│   │   ├── Usage/                     # Daily timeline, session history, charts
│   │   ├── Policies/                  # Policy list & visual rule editor
│   │   ├── Devices/                   # Enrolled devices & pairing modal
│   │   ├── Settings/                  # Preferences, startup, data retention
│   │   └── Diagnostics/               # Sync state, queue count, health audit
│   │
│   ├── Application/                   # Application services & orchestration
│   │   ├── Services/
│   │   │   ├── DeviceService.swift    # Pairing orchestration & key management
│   │   │   ├── PolicyService.swift    # Policy cache & deterministic evaluation
│   │   │   ├── UsageService.swift     # Foreground tracking & state management
│   │   │   ├── TimerService.swift     # Monotonic timer & usage checkpointing
│   │   │   ├── EnforcementService.swift # Local warning & notification dispatch
│   │   │   ├── SyncService.swift      # REST synchronization with backoff
│   │   │   └── RealtimeService.swift  # WebSocket hub client
│   │   └── Coordinators/
│   │       ├── CrashRecoveryService.swift # Unfinished session recovery
│   │       └── MenuBarCoordinator.swift   # Status bar icon & quick menu
│   │
│   ├── Domain/                        # Pure business logic (Zero UI dependencies)
│   │   ├── Entities/
│   │   │   ├── ApplicationTarget.swift # Bundle ID, display name, category
│   │   │   ├── UsageSession.swift     # Session start, end, duration, date
│   │   │   ├── Policy.swift           # Daily limits, warning thresholds, targets
│   │   │   ├── Device.swift           # Device status, enrollment metadata
│   │   │   └── Event.swift            # Canonical FocusGuard event envelopes
│   │   ├── StateMachines/
│   │   │   ├── UsageStateMachine.swift # NO_TARGET -> ACTIVE -> IDLE -> PAUSED
│   │   │   └── DeviceStateMachine.swift # UNREGISTERED -> PAIRING -> ACTIVE -> REVOKED
│   │   └── Policies/
│   │       ├── PolicyEngine.swift     # Deterministic evaluation (ALLOW, WARN, ENFORCE)
│   │       ├── ProtectedAppDenylist.swift # Safety validation (Finder, System Settings)
│   │       └── ClockGuard.swift       # Monotonic clock anti-tamper validation
│   │
│   ├── Infrastructure/                # Platform adapters & hardware interfaces
│   │   ├── ActivityMonitoring/
│   │   │   ├── ForegroundAppProvider.swift # NSWorkspace.shared wrapper & mock
│   │   │   ├── IdleDetector.swift          # CGEventSource idle inspection
│   │   │   └── LockStateMonitor.swift      # DistributedNotification lock/sleep
│   │   ├── Persistence/
│   │   │   ├── DatabaseManager.swift       # SQLite WAL database connection
│   │   │   ├── Schema.swift                # Tables, indexes, migrations
│   │   │   └── Repositories/
│   │   │       ├── DeviceRepository.swift
│   │   │       ├── PolicyRepository.swift
│   │   │       ├── UsageRepository.swift
│   │   │       └── EventQueueRepository.swift
│   │   ├── Security/
│   │   │   ├── KeychainCredentialStore.swift # Apple Security Framework wrapper
│   │   │   └── CryptoService.swift           # CryptoKit Ed25519 key generation
│   │   ├── Notifications/
│   │   │   └── UserNotificationAdapter.swift # UNUserNotificationCenter wrapper
│   │   └── Logging/
│   │       └── AppLogger.swift               # Apple OSLog categorized subsystem
│   │
│   └── Shared/
│       ├── DesignSystem/              # Typography, colors, card containers
│       └── Extensions/                # Foundation & SwiftUI helper extensions
│
├── FocusGuardTests/                   # Automated Unit & Integration Tests
│   ├── PolicyEngineTests.swift
│   ├── UsageStateMachineTests.swift
│   ├── TimerEngineTests.swift
│   ├── EventQueueTests.swift
│   ├── SQLiteRepositoryTests.swift
│   └── VerticalSliceTests.swift
│
└── FocusGuardUITests/                 # UI & Accessibility Tests
```

---

## 3. Core State Machines & Data Flow

### 3.1 Usage Tracking State Machine
```
[NO_TARGET]
    │  Target app enters foreground
    ▼
[ACTIVE] ──(idle > 60s)───────────────► [IDLE]
    │                                      │
    │  (Screen locked / system sleep)      │ (User returns input)
    ▼                                      ▼
[PAUSED] ◄─────────────────────────── [ACTIVE]
    │
    │  (User switches away or quits)
    ▼
[SESSION_ENDED] ──► Persist to SQLite ──► Enqueue Event
```

### 3.2 Monotonic Clock Guard & Anti-Tamper
To protect against time manipulation (e.g. changing system clock backwards):
- `ClockGuard` samples `CLOCK_MONOTONIC_RAW` via `clock_gettime()`.
- Every active session duration is computed strictly as:
  $$\Delta t = \text{monotonic\_now} - \text{monotonic\_start}$$
- Wall clock changes do not extend attention budgets or reset accumulated daily usage.

### 3.3 Offline Event Queue & Idempotent Synchronization
1. Every domain event receives a globally unique UUID: `evt_<uuid>`.
2. Events are immediately committed to local SQLite in `pending_events` with `status = 'PENDING'`.
3. The sync engine flushes batches to `POST /api/v1/events/batch`.
4. The server responds with acknowledged IDs.
5. SQLite commits `status = 'SYNCED'` within a transaction.
6. If offline, the queue retries using exponential backoff ($2s, 4s, 8s, \dots, \max 60s$).

---

## 4. Protected Applications & Safety Invariants

The `ProtectedAppDenylist` unconditionally blocks enforcement against:
- `com.apple.finder`
- `com.apple.loginwindow`
- `com.apple.systempreferences` / `com.apple.systemsettings`
- `com.apple.ActivityMonitor`
- `com.apple.dock`
- `com.apple.Terminal` (in development mode)

Any policy attempting to apply enforcement to these targets is downgraded to `ALLOW` with an alert logged to `OSLog`.
