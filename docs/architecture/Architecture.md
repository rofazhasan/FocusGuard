# FocusGuard Architecture Specification

## 1. Architectural Philosophy

FocusGuard is designed as a **Local-First, Cloud-Synchronized Attention Enforcement System**.

### Design Principles:
1. **Local-First Autonomy**: Devices evaluate attention limits locally using cached policies without requiring an active internet connection.
2. **Native Subsystem Integration**: Uses official macOS Screen Time APIs (`FamilyControls`, `DeviceActivity`, `ManagedSettings`) and Android platform features (`UsageStatsManager`, `VpnService`, `Room`).
3. **Cross-Device Telemetry Aggregation**: Real-time cross-device policy sync via WebSockets.
4. **Zero Monoliths**: Clean modular architecture separating UI, Domain Engine, Platform Adapters, Data Persistence, Sync, and Security.

---

## 2. Platform Component Architecture

```
                    +------------------------------------+
                    |          FOCUSGUARD CLOUD          |
                    |      (Go 1.22 / Chi / PostgreSQL)   |
                    +------------------+-----------------+
                                       |
                         REST / WebSockets (TLS 1.3)
                                       |
            +--------------------------+--------------------------+
            |                                                     |
  +---------v----------+                                +---------v----------+
  |    macOS CLIENT    |                                |   ANDROID CLIENT   |
  |  (Swift / SwiftUI) |                                |  (Kotlin / Compose)|
  +---------+----------+                                +---------+----------+
            |                                                     |
+-----------+------------+                            +-----------+------------+
| - FamilyControls       |                            | - UsageStatsManager    |
| - DeviceActivity       |                            | - VpnService           |
| - ManagedSettings      |                            | - Room Database        |
| - SwiftData / Keychain |                            | - WorkManager / KS     |
+------------------------+                            +------------------------+
```

---

## 3. Layer Separation Protocol

Each platform client and backend service follows clean strict layering:

1. **Presentation (UI Layer)**: Views, view-models, state managers (SwiftUI / Jetpack Compose / REST JSON handlers).
2. **Domain Layer**: Pure business logic (Policy evaluation engine, threshold calculation, schedule matcher, monotonic clock checker).
3. **Platform Adapter Layer**: Platform-specific system API wrappers (`FamilyControls` Manager, `UsageStatsManager` Reader, `VpnService` DNS Sinkhole).
4. **Data & Persistence Layer**: Repositories, database engines (PostgreSQL, SwiftData, Room DB, Keychain, Keystore).
5. **Sync Engine**: WebSocket client/hub, HTTP delta uploaders, offline queue managers.

---

## 4. Policy Execution Pipeline

```
Policy Definition -> Local Engine -> OS Adapter -> Native Enforcement Shield
```

1. **Policy Input**: User configures daily limit (e.g. YouTube: 1800s/day).
2. **Policy Engine**: Calculates remaining budget = `LimitSeconds - CumulativeUsageSeconds`.
3. **Threshold Detection**:
   - **macOS**: `DeviceActivityEvent` triggers out-of-process callback in `DeviceActivityMonitorExtension`.
   - **Android**: `UsageStatsManager` worker detects duration target hit.
4. **Shield Activation**:
   - **macOS**: `ManagedSettingsStore().shield.applications` blocks app launch; `shield.webDomains` blocks web access.
   - **Android**: Displays full-screen immutable lock activity; `VpnService` drops matching DNS requests.
