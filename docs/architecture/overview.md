# Architecture Overview

FocusGuard is a **consent-based, multi-device attention management and policy enforcement platform**.

---

## Core System Axioms

1. **The Server is the Policy Authority**: All policy definitions, versioning, quota aggregation, and audit ledgers originate from and are validated by the centralized backend.
2. **The Device is the Enforcement Authority**: The local device hardware executes actual blocking actions using native operating system frameworks (`ManagedSettingsStore` on macOS, `VpnService` + `UsageStats` on Android).
3. **Consent-First Architecture**: Remote management requires explicit local authorization via 6-character pairing codes or QR codes. FocusGuard rejects covert remote spyware mechanisms.
4. **Offline Autonomy**: Enrolled devices cache their policy rules locally and continue enforcing limits without requiring constant network connectivity.
5. **Data Minimization Guarantee**: No screen pixels, keystrokes, personal messages, or full packet payloads are ever captured or transmitted. Only discrete elapsed time totals are synchronized.

---

## High-Level Topology

```
                  ┌─────────────────────────────────────────┐
                  │          FocusGuard Cloud Server        │
                  │  - Go 1.22 / Chi REST API & WS Hub     │
                  │  - Policy Engine & Aggregation Service  │
                  │  - SQLite (WAL) / PostgreSQL Database   │
                  └────────────────────┬────────────────────┘
                                       │
            ┌──────────────────────────┴──────────────────────────┐
            │ Real-Time WebSocket (ws://) & REST API (https://)    │
            ▼                                                     ▼
┌───────────────────────────────┐             ┌───────────────────────────────┐
│     macOS Enrolled Node       │             │     Android Enrolled Node     │
│  - ScreenTime FamilyControls  │             │  - UsageStatsManager Tracker  │
│  - ManagedSettingsStore Shield│             │  - VpnService RFC 1035 Parser │
│  - Monotonic Clock Guard      │             │  - Local Room Cache (Offline) │
└───────────────────────────────┘             └───────────────────────────────┘
```
