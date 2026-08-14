# Changelog

All notable changes to the FocusGuard platform are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-08-14

### Added
- **Multi-Device Consent-Based Architecture**:
  - 6-character pairing code generation (`FG-XXXXXX`) with 5-minute cryptographic TTL.
  - Device claim endpoint (`POST /api/v1/enrollment/claim`) with role bindings (`OWNER`, `MANAGED_USER`).
  - Scoped policy assignments targeting specific devices or the entire fleet.
- **Native macOS Enforcement Layer**:
  - `FamilyControls` authorization flow and `ManagedSettingsStore` application shield integration.
  - Live frontmost application and active browser tab collector daemon (`osascript`).
  - Proof A verified monotonic clock drift protection (< 0.0001s).
- **Native Android Enforcement Layer**:
  - Foreground tracking with `UsageStatsManager` and midnight date-partition normalizer.
  - RFC 1035 UDP DNS packet parser and `NXDOMAIN` (RCODE 3) synthesizer for restricted domains via `VpnService`.
  - Offline Room database caching for local policy evaluation.
- **Backend Services & Persistence**:
  - Dual-mode database engine: embedded SQLite with WAL mode (`PRAGMA journal_mode=WAL`) and PostgreSQL fallback.
  - Idempotent remote command dispatcher (`POST /api/v1/commands/dispatch`) with time-to-live boundaries.
  - Real-time WebSocket event broadcaster for `USAGE_TICK`, `LIMIT_REACHED`, `DEVICE_ENROLLED`, `POLICY_UPDATED`, and `REMOTE_COMMAND`.
  - Immutable audit logging ledger (`GET /api/v1/audit/logs`).
- **Web Command Center & Managed Device Dual View**:
  - Fleet Command Center for policy definition, live metric monitoring, and device pairing.
  - Transparent Managed Device View displaying active shields, permission health, and restriction status.
  - Simulated cross-device usage delta ingestion tool.
