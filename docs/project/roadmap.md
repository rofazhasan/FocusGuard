# Engineering Roadmap

---

## Phase 1: Core Platform & Single-Device Enforcement (Completed)
- [x] Go backend REST API & embedded SQLite engine with WAL mode.
- [x] macOS Screen Time `FamilyControls` & `ManagedSettingsStore` integration.
- [x] Android `UsageStatsManager` foreground watcher & RFC 1035 UDP DNS sinkhole.
- [x] Real macOS activity collector daemon.

---

## Phase 2: Multi-Device Platform & Consent Protocol (Completed)
- [x] Ephemeral 6-character device enrollment protocol (5-min TTL, QR payload).
- [x] Scoped policy assignments targeting specific devices or the entire fleet.
- [x] Idempotent remote command dispatcher (`REMOTE_FOCUS_START`).
- [x] Real-time WebSocket event fan-out & live audit ledger.
- [x] Web Command Dashboard with Owner Control Center and Managed Device dual-view.

---

## Phase 3: Advanced Intelligence & Enterprise Extensibility (Future)
- [ ] Windows native client utilizing Windows Filtering Platform (WFP).
- [ ] iOS native client utilizing `DeviceActivityReport` extensions.
- [ ] On-device machine learning for automatic context-aware distraction categorization.
- [ ] Hardware FIDO2 / YubiKey physical unenrollment authorization.
