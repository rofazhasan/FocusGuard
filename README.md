# FOCUSGUARD

> **Tagline**: *"Your attention. Your rules."*

FocusGuard is a high-performance, cross-device attention enforcement platform for **macOS** and **Android**, powered by a **Go** micro-backend and **PostgreSQL**.

Unlike traditional screen-time trackers that only record app usage, FocusGuard proactively **enforces user-defined attention budgets and focus sessions** across multiple enrolled devices in real-time, with local-first offline resilience and tamper-resistant security mechanisms.

---

## 🚀 Key Features

- **Attention Budgets**: Define precise daily/weekly limits for specific applications, websites, or app categories (e.g., YouTube: 30m/day, Social Media: 60m/day).
- **Cross-Device Shared Limits**: Aggregates usage across macOS laptops and Android phones. When total attention budget is exhausted across devices, restrictions trigger everywhere simultaneously.
- **Native OS Enforcement**:
  - **macOS**: Built using Apple's official Screen Time frameworks (`FamilyControls`, `DeviceActivity`, `ManagedSettings`) with zero kernel hacks or sandbox bypasses.
  - **Android**: Foreground app usage monitoring (`UsageStatsManager`) paired with a local DNS sinkhole (`VpnService`) for privacy-first website blocking.
- **Offline Resilience**: Local policy caching ensures enforcement continues uninterrupted during internet disconnects. Reconnection automatically delta-syncs telemetry without double-counting.
- **Focus Sessions**: On-demand focus countdowns (15m, 30m, 45m, 60m) that temporarily restrict distracting platforms while keeping essential emergency/work tools accessible.
- **Anti-Tamper Resilience**: Utilizes system monotonic timers (`CLOCK_MONOTONIC` / `elapsedRealtime()`) and server clock drift detection to block system wall-clock manipulation.
- **Executive Analytics Dashboard**: Modern, calm visual telemetry showing total focus time, active budget adherence, top distraction drivers, and device status.

---

## 🏗️ Repository Architecture

FocusGuard is organized as a monorepo:

```
focusguard/
├── apps/
│   ├── macos/           # Native macOS Application (Swift, SwiftUI, FamilyControls, SwiftData)
│   └── android/         # Native Android Application (Kotlin, Jetpack Compose, UsageStats, Room)
├── backend/
│   ├── cmd/server/      # Backend Entrypoint (Go, Chi/Gin)
│   ├── internal/        # Domain Services (Auth, Devices, Policies, Usage, Sync, Analytics, Events)
│   ├── pkg/             # Shared Utilities (Database, Logger)
│   └── migrations/      # PostgreSQL Schema Migration DDLs
├── packages/
│   └── api-contracts/   # OpenAPI 3.0 Specifications & Schemas
├── docs/
│   ├── architecture/    # Architectural Design & Security Specification
│   ├── api/             # API Reference Documentation
│   ├── database/        # ER Diagrams & Database Design
│   └── testing/         # Integration & E2E Testing Guidelines
├── infra/
│   ├── docker/          # Dockerfiles & Multi-stage container builds
│   └── postgres/        # Database initialization scripts
└── .github/
    └── workflows/       # CI/CD Pipelines
```

---

## 🛠️ Quick Start (Backend Infrastructure)

### Prerequisites
- [Go 1.22+](https://go.dev/)
- [Docker & Docker Compose](https://www.docker.com/)

### 1. Launch Services with Docker Compose

```bash
cd infra/docker
docker-compose up -d --build
```

This starts PostgreSQL on port `5432` and the FocusGuard Go Backend API server on port `8080`.

### 2. Verify Backend Health

```bash
curl http://localhost:8080/health
# Response: {"status":"UP","timestamp":"2026-08-12T...","version":"1.0.0"}
```

---

## 📚 Documentation Index

- [System Architecture Specification](docs/architecture/Architecture.md)
- [Security & Anti-Tamper Model](docs/architecture/Security.md)
- [API Specification & Event Protocols](docs/api/API.md)
- [Database Schema & ER Diagrams](docs/database/Database.md)
- [Testing & Quality Assurance Plan](docs/testing/Testing.md)
- [Developer Onboarding & Workflow](docs/Development.md)

---

## ⚖️ License & Compliance

FocusGuard operates strictly within official OS security policies and privacy guidelines. It does not contain kernel exploits, stealth persistence, or OS security bypasses.
