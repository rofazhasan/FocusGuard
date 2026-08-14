# Distributed System Architecture

This document specifies the software architecture, boundaries, and internal components across the FocusGuard ecosystem.

---

## Component Decomposition

### 1. Backend Service Layer (`backend/`)
- **HTTP/REST Ingress (Chi Router)**: Handles authentication, device registration, pairing token lifecycles, and policy management.
- **WebSocket Hub (`backend/internal/events`)**: Maintains active persistent bidirectional connections to enrolled devices and web clients for sub-second event broadcasts.
- **Policy Evaluator (`backend/internal/policies`)**: Implements deterministic rule evaluation, hierarchical subdomain matching, and 6-tier conflict resolution.
- **Usage Ingestion Service (`backend/internal/usage`)**: Idempotently aggregates usage deltas across multi-device nodes and computes threshold breaches.
- **Remote Command Engine (`backend/internal/commands`)**: Validates and issues time-bounded commands (`REMOTE_FOCUS_START`, `POLICY_UPDATE`).
- **Audit Logging Subsystem (`backend/internal/audit`)**: Persists structured immutable event records for all administrative actions.

---

### 2. Native macOS Client Layer (`apps/macos/`)
- **Activity Collector**: Queries active application bundle IDs and browser tab domains via AppleScript/Workspace APIs.
- **Clock Drift Watchdog**: Verifies wall-clock progression against `mach_absolute_time()` to identify manual system clock tampering.
- **Screen Time Shield Bridge**: Configures Apple's `ManagedSettingsStore` out-of-process shields for blocked bundles and domains.

---

### 3. Native Android Client Layer (`apps/android/`)
- **Foreground Session Watcher**: Leverages `UsageStatsManager` to track active application sessions and splits midnight transitions cleanly.
- **VpnService Loopback Sinkhole**: Runs a local TUN interface that parses incoming UDP port 53 DNS queries and returns `NXDOMAIN` (RCODE 3) for blocked domains.
- **Room SQLite Cache**: Persists policy bundles locally to guarantee 100% offline enforcement uptime.

---

### 4. Web Command Center (`apps/web/`)
- **Owner Control Center**: Real-time management interface for policy definition, device pairing, and fleet metric aggregation.
- **Managed Device Dual View**: Transparent mode showing active shields and permission health on student/child screens.
- **Simulator & Ingestion Tool**: Interactively validates cross-device shared budget exhaustion.
