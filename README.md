# FocusGuard

<p align="center">
  <strong>One policy. Every protected device.</strong><br>
  <em>A consent-based, multi-device attention enforcement and digital wellbeing platform.</em>
</p>

<p align="center">
  <a href="#key-features">Key Features</a> •
  <a href="#system-architecture">Architecture</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#documentation-index">Documentation</a> •
  <a href="#security--privacy">Security & Privacy</a> •
  <a href="#academic-context">Academic Context</a>
</p>

---

## 🛡️ What is FocusGuard?

**FocusGuard** is an open-source, multi-device attention enforcement platform engineered to bridge the gap between simple screen-time passive trackers and enforceable digital boundaries.

Traditional screen-time tools merely report historical usage or rely on easily bypassed local timers. FocusGuard introduces **server-authoritative distributed attention budgets** that are locally enforced across macOS laptops and Android devices in real-time. When a shared daily budget (e.g., *YouTube: 30 minutes/day*) is reached across any combination of enrolled devices, native OS shields and network DNS sinkholes engage simultaneously.

```
REAL USAGE (macOS / Android UsageStats)
                  ↓
       REAL USAGE AGGREGATION
                  ↓
      DETERMINISTIC POLICY ENGINE
                  ↓
          THRESHOLD REACHED
                  ↓
     REAL OS & NETWORK ENFORCEMENT
 (macOS ManagedSettings / Android VpnService)
                  ↓
    PERSISTENT AUDIT & SQLITE/POSTGRES
                  ↓
      REAL-TIME WEBSOCKET HUB
                  ↓
       LIVE COMMAND DASHBOARD
```

---

## 🚀 Key Features

- **Cross-Device Shared Budgets**: Define unified attention limits for apps, websites, or categories (e.g. Social Media: 45 min/day) aggregated across macOS laptops and Android mobile devices.
- **Native OS Enforcement (Zero Kernel Exploits)**:
  - **macOS**: Built on Apple Screen Time APIs (`FamilyControls`, `ManagedSettings`, `DeviceActivity`) for out-of-process application and web domain shields.
  - **Android**: Foreground application tracking via `UsageStatsManager` combined with a local `VpnService` DNS sinkhole returning `NXDOMAIN` for restricted domains.
- **Consent-Based Device Enrollment**: Secure 6-character pairing codes (e.g. `FG-8492`) and signed QR codes with a 5-minute TTL. No hidden profiles or unauthorized remote access.
- **Offline Autonomy**: Enrolled devices cache their `lastAppliedVersion` of policies. If internet connectivity drops, local enforcement continues without interruption. Delta synchronization reconciles usage upon reconnection without double-counting.
- **Remote Focus Sessions**: Account owners can dispatch timed focus countdowns (15m, 30m, 45m, 60m) that temporarily restrict distracting platforms while whitelisting educational and emergency tools.
- **Transparent Audit Ledger**: Every policy creation, device pairing, and enforcement action is immutably recorded with timestamps.
- **Anti-Tampering Monotonic Guards**: Verifies hardware monotonic timers (`CLOCK_MONOTONIC_RAW` / `SystemClock.elapsedRealtime()`) against wall-clock time to prevent clock manipulation.

---

## 🏗️ System Architecture

FocusGuard is structured as a modular distributed monorepo:

```
focusguard/
├── apps/
│   ├── macos/           # Native macOS Application (Swift, SwiftUI, FamilyControls, ManagedSettings)
│   ├── android/         # Native Android Application (Kotlin, Jetpack Compose, UsageStats, VpnService, Room)
│   └── web/             # Real-Time Web Command Dashboard & Managed Device View (Vanilla HTML/CSS/JS)
├── backend/
│   ├── cmd/server/      # Backend Entrypoint (Go 1.26, Chi HTTP router)
│   ├── internal/        # Domain Services (Auth, Devices, Enrollment, Policies, Usage, Focus, Commands, Audit, Collector)
│   ├── pkg/             # Database (SQLite / PostgreSQL dual-mode) & Structured Logger
│   └── migrations/      # PostgreSQL & SQLite Schema DDLs
├── packages/
│   └── api-contracts/   # OpenAPI 3.0 Specifications & WebSocket Protocol Schemas
└── docs/                # Comprehensive Diátaxis Documentation Suite
```

---

## ⚡ Quick Start

### Prerequisites
- [Go 1.22+](https://go.dev/)
- [Node.js 18+](https://nodejs.org/) (for Web Dashboard)
- [Xcode 15+](https://developer.apple.com/xcode/) (for macOS Client)
- [Android Studio Iguana+](https://developer.android.com/studio) (for Android Client)

### 1. Launch the Backend Server
```bash
cd backend
go run cmd/server/main.go
```
*The Go server initializes the embedded SQLite database (`focusguard.db`) and starts listening on port `8080`.*

### 2. Launch the Web Command Center
```bash
cd apps/web
PORT=3001 node server.js
```
Open **[http://localhost:3001](http://localhost:3001)** in your web browser.

### 3. Verify System Health
```bash
curl http://localhost:8080/health
# Response: {"status":"UP","timestamp":"2026-08-14T...","version":"1.0.0"}
```

---

## 📚 Documentation Index

FocusGuard follows the **Diátaxis documentation framework**:

| Category | Documentation Sections |
|---|---|
| **🚀 Getting Started** | [Installation](docs/getting-started/installation.md) • [Quick Start](docs/getting-started/quick-start.md) • [First Policy](docs/getting-started/first-policy.md) • [First Device](docs/getting-started/first-device.md) |
| **📖 Tutorials** | [Owner Setup](docs/tutorials/owner-setup.md) • [Enroll Android Device](docs/tutorials/enroll-android-device.md) • [Configure macOS](docs/tutorials/configure-macos.md) • [First Focus Session](docs/tutorials/create-first-focus-session.md) |
| **🛠️ How-To Guides** | [Block an App](docs/how-to/block-an-app.md) • [Block a Website](docs/how-to/block-a-website.md) • [Create Time Limit](docs/how-to/create-time-limit.md) • [Troubleshoot VPN](docs/how-to/troubleshoot-vpn.md) |
| **🏛️ Architecture** | [Overview](docs/architecture/overview.md) • [System Architecture](docs/architecture/system-architecture.md) • [Device Enrollment](docs/architecture/device-enrollment.md) • [Policy Engine](docs/architecture/policy-engine.md) |
| **📑 Reference** | [REST API Spec](docs/reference/api.md) • [Authentication](docs/reference/authentication.md) • [Database Schema](docs/reference/database.md) • [Configuration](docs/reference/configuration.md) |
| **💡 Concepts** | [Enforcement Models](docs/concepts/enforcement.md) • [Attention Budgets](docs/concepts/attention-budget.md) • [Domain Filtering](docs/concepts/domain-filtering.md) • [Device Trust](docs/concepts/device-trust.md) |
| **🔒 Security & Privacy** | [Threat Model](docs/security/threat-model.md) • [Data Collection & Privacy](docs/privacy/data-collection.md) • [Vulnerability Reporting](docs/security/vulnerability-reporting.md) |
| **📋 Architectural Decisions** | [ADR 0001: Documentation](docs/decisions/0001-documentation.md) • [ADR 0004: Policy Engine](docs/decisions/0004-policy-engine.md) • [ADR 0005: Android VPN](docs/decisions/0005-android-vpn.md) |

---

## 🔒 Security & Privacy

FocusGuard operates on a strict **Data Minimization & Transparency Guarantee**:
- **Zero Content Inspection**: FocusGuard never captures keystrokes, messages, screen pixels, photos, or browsing history.
- **Aggregated Metadata Only**: Only target labels (e.g. `youtube.com`) and elapsed seconds are tracked to evaluate configured policy limits.
- **Consent-First Architecture**: Remote management requires explicit local enrollment authorization on the target device.

For vulnerability disclosures, see [SECURITY.md](SECURITY.md).

---

## 🎓 Academic Context

FocusGuard was developed as a Capstone Project for **CSE 3200: Software Development Project** at **Rajshahi University of Engineering & Technology (RUET)**.

- **Academic Supervisor**: Prof. Boshir Ahmed, Department of Computer Science & Engineering, RUET
- **Team**: 2 Developers (Developer A: macOS & UI Architect; Developer B: Android & Backend Platform Engineer)

---

## 📄 License

FocusGuard is open-source software licensed under the [Apache License, Version 2.0](LICENSE).
