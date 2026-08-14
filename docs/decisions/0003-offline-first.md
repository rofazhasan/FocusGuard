# ADR 0003: Offline-First Policy Caching and Delta Reconciliation

- **Status**: Accepted
- **Date**: 2026-08-14
- **Author**: FocusGuard Systems Architecture Team

---

## Context
A major vulnerability in cloud-dependent attention tools is that users can disable Wi-Fi or enable Airplane Mode to bypass remote enforcement.

---

## Decision
We established an offline-first client architecture:
1. Devices store active policy bundles in local persistent storage (Room SQLite on Android, CoreData on macOS).
2. Local enforcement engines evaluate limits continuously against local storage.
3. Network usage increments queue locally and sync idempotently upon reconnection.

---

## Consequences
- **Positive**: Enforcement cannot be bypassed by disconnecting from the internet.
- **Negative**: Edge case where concurrent usage on two disconnected devices briefly exceeds the shared limit until reconnection.
