# System Requirements Specification (SRS)

This document formalizes the Functional and Non-Functional Requirements for FocusGuard.

---

## 1. Functional Requirements (FR)

- **FR-01 (Multi-Device Enrollment)**: The system shall issue cryptographically random 6-character pairing codes with a strict 300-second TTL to enroll client devices.
- **FR-02 (Policy Definition & Scoping)**: The system shall permit the account owner to define attention limits on apps, website domains, or categories scoped to specific devices or the entire fleet.
- **FR-03 (Cross-Device Quota Ingestion)**: The system shall idempotently aggregate usage duration deltas across enrolled nodes and compute shared threshold breaches.
- **FR-04 (Native macOS Enforcement)**: The macOS client shall engage out-of-process shields via `ManagedSettingsStore` when limits are exceeded.
- **FR-05 (Native Android Network Filter)**: The Android client shall intercept DNS queries via local `VpnService` and synthesize RFC 1035 `NXDOMAIN` (RCODE 3) responses for blocked domains.
- **FR-06 (Offline Autonomy)**: Client devices shall cache active policies in local SQLite/CoreData databases and continue local enforcement when disconnected.
- **FR-07 (Remote Focus Lockdown)**: The system shall allow owners to dispatch immediate focus countdown sessions with allowlist overrides.
- **FR-08 (Immutable Audit Ledger)**: All policy actions, device pairings, and command dispatches shall be recorded in `audit_logs`.

---

## 2. Non-Functional Requirements (NFR)

- **NFR-01 (Performance & Latency)**: Real-time WebSocket event fan-out latency shall be < 100ms. Local DNS evaluation latency on Android shall be < 2ms.
- **NFR-02 (Anti-Tampering)**: The client shall monitor hardware monotonic timers to detect wall-clock manipulation.
- **NFR-03 (Zero Root Privilege)**: The platform shall execute without requiring root (`sudo`) privileges on macOS or rooted bootloaders on Android.
