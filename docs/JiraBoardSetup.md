# FocusGuard Jira Board Setup & Agile Workflow Guide

This guide details step-by-step instructions for importing the FocusGuard project backlog, Epics, Stories, and Tasks directly into **Jira Cloud** or **Jira Software**, configuring the Agile Board, and running a multi-layered cross-platform enforcement workflow.

---

## 1. Quick 1-Click Jira Import (via CSV)

FocusGuard provides a pre-formatted Jira CSV import file containing all **10 FG-ENF Epics**, **20 User Stories & Tasks**, priorities, labels, and acceptance criteria:
📄 **File Location**: [`docs/focusguard-jira-export.csv`](file:///Users/md.rofazhasanrafiu/coding/FocusGuard/docs/focusguard-jira-export.csv)

### Step-by-Step CSV Import Instructions:

1. Log into your **Jira Cloud** instance (`https://your-domain.atlassian.net`).
2. Click on **Settings** (⚙️ cog icon in top right) -> **System** -> **External System Import**.
3. Select **CSV** import option.
4. Click **Choose File** and select `docs/focusguard-jira-export.csv` from the repo.
5. In **Project Selection**, choose your project key (`FG-ENF` / `FocusGuard`).
6. Map CSV fields to Jira fields:
   - `Issue Type` -> **Issue Type**
   - `Summary` -> **Summary**
   - `Description` -> **Description**
   - `Epic Name` -> **Epic Name**
   - `Epic Link` -> **Epic Link**
   - `Priority` -> **Priority**
   - `Labels` -> **Labels**
7. Click **Begin Import**. Jira will instantly create all 10 Epics and linked Stories/Tasks!

---

## 2. Jira Epics Architecture (`FG-ENF`)

```
FG-ENF Browser Enforcement
├── FG-101: WebExtensions Shared Core Architecture
├── FG-102: Hostname-Aware Domain Matcher
└── FG-103: FocusGuard Block Page & Interceptor

FG-ENF Android Enforcement
├── FG-201: Android Jetpack Compose UI & Room Database
├── FG-202: UsageStatsManager Foreground Activity Tracking
└── FG-203: Immutable Full-Screen Lock Overlay

FG-ENF macOS Enforcement
├── FG-301: macOS SwiftUI Navigation & SwiftData Models
├── FG-302: FamilyControls Authorization Workflow
└── FG-303: ManagedSettings Custom Shield Extension

FG-ENF Network Engine
├── FG-401: VpnService Local DNS Sinkhole
├── FG-402: Trie-based DomainPolicyCache
└── FG-403: Application-Aware Network Decision Engine

FG-ENF Policy Engine
├── FG-501: Shared Policy Model & Evaluator
├── FG-502: Progressive Warning Thresholds
├── FG-503: Policy Simulator & Conflict Detector
└── FG-504: Policy Explainer (Why Blocked?)

FG-ENF Usage Detection
├── FG-601: Active Visibility Time & 60s Idle Detector
├── FG-602: Session State Machine
└── FG-603: Midnight Session Partitioner

FG-ENF Synchronization
├── FG-701: Go WebSocket Broadcast Hub
├── FG-702: Monotonic Policy Versioning & Offline Cache
└── FG-703: Cross-Device Shared Attention Budget

FG-ENF Analytics
├── FG-801: Transparent Attention Score Calculator
├── FG-802: Daily Visual Activity Timeline
└── FG-803: Weekly Trends & Distraction Breakdown

FG-ENF Security
├── FG-901: Monotonic Clock Anti-Tamper Detector
├── FG-902: Secure Token Storage (Keychain / Keystore)
└── FG-903: Fleet Protection Health & Tamper Telemetry

FG-ENF Testing
├── FG-1001: Go Backend Test Suite
├── FG-1002: Browser Extension Core Test Suite
└── FG-1003: Native Platform Proof Harnesses
```

---

## 3. Two-Developer Agile Roles

- **Developer A**: macOS Screen Time (`FamilyControls` / `ManagedSettings`), WebExtensions Browser Extension, Frontend UI/UX, Policy Simulator.
- **Developer B**: Android Enforcement (`VpnService` / `UsageStatsManager`), Go Backend, WebSocket Hub, Analytics & Security Pipeline.
- **Shared**: Policy Engine Specification, Cross-Platform Domain Matching, Monotonic Sync, and E2E Integration Testing.
