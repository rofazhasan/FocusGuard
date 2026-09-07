# FocusGuard Phase 4 Jira Task Catalog

**Epic ID**: `FG-MAC-400`  
**Epic Title**: FocusGuard Phase 4 macOS Native Client  
**Target Platform**: macOS 13.0+ (Ventura, Sonoma, Sequoia)  
**Status**: IN PROGRESS  

---

## Definition of Done (DoD)

Every task in this catalog requires:
- [ ] Requirements fully understood and mapped to FocusGuard architecture.
- [ ] Layered Clean Architecture respected (Zero macOS APIs in Domain layer).
- [ ] Implementation complete and verified on macOS.
- [ ] Unit tests written and passing.
- [ ] Integration tests passing where applicable.
- [ ] Error handling and edge conditions verified.
- [ ] No hardcoded secrets or credentials logged.
- [ ] Documentation updated.

---

## Tasks Breakdown (FG-MAC-401 to FG-MAC-451)

| Task ID | Summary | Component | Status |
| :--- | :--- | :--- | :--- |
| **FG-MAC-401** | Existing System Compatibility Audit | Documentation | ✅ DONE |
| **FG-MAC-402** | macOS Architecture Specification | Documentation | ✅ DONE |
| **FG-MAC-403** | Swift Package & Project Structure | Infrastructure | 🔄 IN PROGRESS |
| **FG-MAC-404** | Domain Models & Entity Definitions | Domain | 🔄 IN PROGRESS |
| **FG-MAC-405** | Dependency Injection & App State Container | Application | 🔄 IN PROGRESS |
| **FG-MAC-406** | Foreground Application Provider Protocol & Adapter | Infrastructure | 🔄 IN PROGRESS |
| **FG-MAC-407** | Application Identity Resolution & Normalization | Domain | 🔄 IN PROGRESS |
| **FG-MAC-408** | Idle State Detection Adapter | Infrastructure | 🔄 IN PROGRESS |
| **FG-MAC-409** | Screen Lock & Session State Monitor | Infrastructure | 🔄 IN PROGRESS |
| **FG-MAC-410** | Sleep and Wake Notification Handling | Infrastructure | 🔄 IN PROGRESS |
| **FG-MAC-411** | Deterministic Usage State Machine | Domain | 🔄 IN PROGRESS |
| **FG-MAC-412** | Monotonic Timer Engine | Application | 🔄 IN PROGRESS |
| **FG-MAC-413** | Crash Recovery & Session Restoration Service | Application | 🔄 IN PROGRESS |
| **FG-MAC-414** | Daily Usage Aggregation Engine | Application | 🔄 IN PROGRESS |
| **FG-MAC-415** | Pure Deterministic Policy Engine | Domain | PLANNED |
| **FG-MAC-416** | Enforcement Coordinator & Warning Dispatcher | Application | PLANNED |
| **FG-MAC-417** | Protected Application Denylist & Safety Filter | Domain | 🔄 IN PROGRESS |
| **FG-MAC-418** | Keychain Credential Storage Service | Infrastructure | 🔄 IN PROGRESS |
| **FG-MAC-419** | Embedded SQLite Database & Migrations | Infrastructure | 🔄 IN PROGRESS |
| **FG-MAC-420** | Offline Durable Event Queue | Application | 🔄 IN PROGRESS |
| **FG-MAC-421** | Device Enrollment & Pairing Workflow | Application | 🔄 IN PROGRESS |
| **FG-MAC-422** | Policy Synchronization Engine | Application | PLANNED |
| **FG-MAC-423** | Device Heartbeat Dispatcher | Application | PLANNED |
| **FG-MAC-424** | Realtime WebSocket Hub Client | Application | PLANNED |
| **FG-MAC-425** | Remote Device Revocation Handler | Application | PLANNED |
| **FG-MAC-426** | Browser Integration Boundary & Extensions Adapter | Application | PLANNED |
| **FG-MAC-427** | Native macOS Menu Bar Item & Quick Menu | Presentation | PLANNED |
| **FG-MAC-428** | Dashboard View & Attention Hero Card | Presentation | PLANNED |
| **FG-MAC-429** | Applications Discovery & Tracking View | Presentation | PLANNED |
| **FG-MAC-430** | Policy Editor & Rule Configuration View | Presentation | PLANNED |
| **FG-MAC-431** | Usage Analytics & Historical Timeline View | Presentation | PLANNED |
| **FG-MAC-432** | Settings & Preferences View | Presentation | PLANNED |
| **FG-MAC-433** | Permission Center & TCC Guidance View | Presentation | PLANNED |
| **FG-MAC-434** | Diagnostics & Fleet Health Inspection View | Presentation | PLANNED |
| **FG-MAC-435** | Single Instance Process Lock Protection | Application | PLANNED |
| **FG-MAC-436** | Concurrency Audit & Actor State Isolation | Architecture | PLANNED |
| **FG-MAC-437** | Comprehensive Unit Test Suite | QA | 🔄 IN PROGRESS |
| **FG-MAC-438** | macOS Integration Test Suite | QA | 🔄 IN PROGRESS |
| **FG-MAC-439** | Offline Chaos & Disconnect Test Suite | QA | PLANNED |
| **FG-MAC-440** | Crash Recovery & Abrupt Termination Tests | QA | PLANNED |
| **FG-MAC-441** | Security & Tamper Resistance Tests | Security | PLANNED |
| **FG-MAC-442** | Performance & CPU Resource Profiling | Performance | PLANNED |
| **FG-MAC-443** | Accessibility & Keyboard Navigation Tests | Accessibility | PLANNED |
| **FG-MAC-444** | Manual QA Execution & Verification Runbook | QA | PLANNED |
| **FG-MAC-445** | macOS CI/CD GitHub Actions Workflow | DevOps | PLANNED |
| **FG-MAC-446** | Application Packaging (.app / .dmg) | DevOps | PLANNED |
| **FG-MAC-447** | Clean Machine Installation Verification | QA | PLANNED |
| **FG-MAC-448** | Staging Environment Deployment Verification | DevOps | PLANNED |
| **FG-MAC-449** | Production Release Build Generation | DevOps | PLANNED |
| **FG-MAC-450** | Phase 4 Documentation & Runbooks | Documentation | PLANNED |
| **FG-MAC-451** | Final End-to-End Acceptance Sign-Off | QA / Lead | PLANNED |
