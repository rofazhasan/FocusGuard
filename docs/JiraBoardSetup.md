# FocusGuard Jira Board Setup & Agile Workflow Guide

This guide details step-by-step instructions for importing the FocusGuard project backlog, Epics, Stories, and Tasks directly into **Jira Cloud** or **Jira Software**, configuring the Agile Board, and running an 8-week (4-Sprint) development workflow.

---

## 1. Quick 1-Click Jira Import (via CSV)

FocusGuard provides a pre-formatted Jira CSV import file containing all **8 Epics**, **24 User Stories & Tasks**, priorities, labels, and acceptance requirements:
📄 **File Location**: [`docs/focusguard-jira-export.csv`](file:///Users/md.rofazhasanrafiu/coding/focusguard/docs/focusguard-jira-export.csv)

### Step-by-Step CSV Import Instructions:

1. Log into your **Jira Cloud** instance (`https://your-domain.atlassian.net`).
2. Click on **Settings** (⚙️ cog icon in top right) -> **System** -> **External System Import**.
3. Select **CSV** import option.
4. Click **Choose File** and select `focusguard-jira-export.csv` from the repo's `docs/` folder.
5. In **Project Selection**, choose your project key (e.g. `FG` / `FocusGuard`).
6. Map CSV fields to Jira fields:
   - `Issue Type` -> **Issue Type**
   - `Issue ID` -> **Issue Key / ID**
   - `Summary` -> **Summary**
   - `Description` -> **Description**
   - `Epic Name` -> **Epic Name**
   - `Epic Link` -> **Epic Link**
   - `Priority` -> **Priority**
   - `Labels` -> **Labels**
7. Click **Begin Import**. Jira will instantly create all 8 Epics and linked Stories/Tasks!

---

## 2. Jira Epics Architecture

```
EPIC 1: Platform Foundation & Infrastructure (FG-EP1)
├── FG-101: Setup monorepo folder structure & Docker Compose environment
├── FG-102: Create PostgreSQL database schema & migration DDL scripts
└── FG-103: Define OpenAPI 3.0 API Specification & contract definitions

EPIC 2: Backend Microservices & API (FG-EP2)
├── FG-201: Implement Auth service (JWT registration, login, refresh)
├── FG-202: Implement Device management service
├── FG-203: Implement Policy CRUD service with versioning
└── FG-204: Implement Usage aggregation endpoint with idempotent session processing

EPIC 3: macOS Client & Screen Time Integration (FG-EP3)
├── FG-301: Create SwiftUI Application architecture & SwiftData models
├── FG-302: Implement FamilyControls authorization request workflow
├── FG-303: Implement DeviceActivityMonitor extension for local threshold triggers
└── FG-304: Implement ManagedSettings custom Shield extensions

EPIC 4: Android Client & Enforcement Subsystem (FG-EP4)
├── FG-401: Create Jetpack Compose UI architecture & Room local database
├── FG-402: Implement UsageStatsManager tracking service
├── FG-403: Implement VpnService local DNS filter for website blocking
└── FG-404: Implement full-screen lock overlay UI for app enforcement

EPIC 5: Cross-Device Synchronization Engine (FG-EP5)
├── FG-501: Implement Go WebSocket broadcast hub
├── FG-502: Implement macOS WebSocket client & offline delta sync queue
├── FG-503: Implement Android WorkManager sync worker & reconnection logic
└── FG-504: Implement server-side cross-device usage limit calculator

EPIC 6: Analytics & Focus Sessions (FG-EP6)
├── FG-601: Implement Focus Session countdown engine (macOS & Android)
├── FG-602: Implement Backend Analytics aggregation queries
└── FG-603: Build UI Analytics dashboards with native charts

EPIC 7: Security & Anti-Tamper Engine (FG-EP7)
├── FG-701: Implement Monotonic clock validation & tampering detector
└── FG-702: Secure token storage (Keychain & Android Keystore integration)

EPIC 8: Quality Assurance & E2E Testing (FG-EP8)
├── FG-801: Write Go integration tests for API endpoints
├── FG-802: Write macOS XCTest unit tests for Policy Engine
└── FG-803: Write Android JUnit/Espresso tests for Room & Usage Engine
```

---

## 3. 4-Sprint Implementation Plan (2 Weeks per Sprint)

### **Sprint 1 (Weeks 1-2): Infrastructure, API Contracts & Backend Core**
- **Goal**: Setup monorepo, Docker Postgres DB, OpenAPI spec, JWT auth, Device & Policy CRUD APIs.
- **Issues**: `FG-101`, `FG-102`, `FG-103`, `FG-201`, `FG-202`, `FG-203`.

### **Sprint 2 (Weeks 3-4): macOS & Android Platform Core Shells**
- **Goal**: Build native SwiftUI & Jetpack Compose apps, Screen Time `FamilyControls` & Android `UsageStatsManager` engine.
- **Issues**: `FG-301`, `FG-302`, `FG-303`, `FG-401`, `FG-402`.

### **Sprint 3 (Weeks 5-6): Network Enforcement, WebSockets & Real-time Sync**
- **Goal**: Android `VpnService` DNS sinkhole, macOS `ManagedSettings` Shields, Go WebSocket hub, Cross-device sync engine.
- **Issues**: `FG-304`, `FG-403`, `FG-404`, `FG-501`, `FG-502`, `FG-503`, `FG-504`.

### **Sprint 4 (Weeks 7-8): Focus Sessions, Security Anti-Tamper & E2E Testing**
- **Goal**: Focus Session countdowns, monotonic clock tampering validation, KeyStore/Keychain security, unit & integration test suites.
- **Issues**: `FG-601`, `FG-602`, `FG-603`, `FG-701`, `FG-702`, `FG-801`, `FG-802`, `FG-803`.

---

## 4. Jira Board Workflow States

Map your Jira Scrum Board columns to the following states:
1. `TO DO` -> Open backlog items.
2. `IN PROGRESS` -> Active development on feature branch.
3. `CODE REVIEW` -> Pull request open on GitHub (`develop` branch).
4. `TESTING / QA` -> Unit & integration test execution.
5. `DONE` -> Merged to `develop`/`main` with green CI pipeline.
