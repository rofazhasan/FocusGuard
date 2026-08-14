# Project Scope & Academic Charter

- **Course**: CSE 3200 Software Development Project
- **Institution**: Department of Computer Science & Engineering, Rajshahi University of Engineering & Technology (RUET)
- **Academic Supervisor**: Prof. Boshir Ahmed

---

## 1. Project Charter
FocusGuard is engineered to build a production-quality, cross-device attention enforcement and digital wellbeing system with zero fake/mock data, real OS API integrations, and robust offline autonomy.

---

## 2. In-Scope Deliverables
- Dual-mode backend service in Go (SQLite WAL / PostgreSQL) with REST & WebSocket APIs.
- Native macOS client using Apple Screen Time frameworks (`FamilyControls`, `ManagedSettings`).
- Native Android client using `UsageStatsManager` and RFC 1035 UDP DNS sinkhole over `VpnService`.
- Web Command Center with Owner Control Center and Managed Device dual-view modes.
- Ephemeral consent-based pairing protocol (6-char codes, 5-min TTL).
- Complete Diátaxis documentation suite, formal test suites, and ADRs.

---

## 3. Out-of-Scope (Deliberate Design Exclusions)
- Invasive keyloggers, screen recording daemons, or covert spyware mechanisms.
- Windows/Linux desktop client ports (reserved for future milestones).
