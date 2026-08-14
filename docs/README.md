# FocusGuard Technical Documentation

Welcome to the FocusGuard engineering and operations documentation suite. This documentation is organized according to the **Diátaxis framework**, categorizing knowledge across four clear modes:

```
                  PRACTICAL GOAL
                       ▲
                       │
       Tutorials       │      How-To Guides
  (Learning-oriented)  │   (Problem-oriented)
                       │
◄──────────────────────┼──────────────────────►
                       │
       Concepts        │        Reference
(Understanding-oriented│ (Information-oriented)
                       │
                       ▼
                 THEORETICAL GOAL
```

---

## 🧭 Navigation Matrix

### 1. 🚀 [Getting Started](getting-started/installation.md)
Step-by-step setup guides for engineers, evaluators, and system operators:
- [Installation](getting-started/installation.md) — System requirements and binary/source builds.
- [Quick Start](getting-started/quick-start.md) — Spin up the full system in under 2 minutes.
- [First Device](getting-started/first-device.md) — Enroll your first macOS or Android node.
- [First Policy](getting-started/first-policy.md) — Define and enforce your initial attention budget.

### 2. 📖 [Tutorials](tutorials/owner-setup.md)
Guided lessons designed to build a complete mental model of FocusGuard:
- [Owner Account Setup](tutorials/owner-setup.md)
- [Enrolling an Android Device](tutorials/enroll-android-device.md)
- [Configuring macOS Screen Time API](tutorials/configure-macos.md)
- [Creating Your First Remote Focus Session](tutorials/create-first-focus-session.md)

### 3. 🛠️ [How-To Guides](how-to/block-an-app.md)
Direct, recipe-driven solutions to common administrative and engineering challenges:
- [Block an Application](how-to/block-an-app.md)
- [Block a Website Domain](how-to/block-a-website.md)
- [Create a Shared Cross-Device Time Limit](how-to/create-time-limit.md)
- [Manage Fleet Devices & Roles](how-to/manage-devices.md)
- [Work in Offline Autonomous Mode](how-to/work-offline.md)
- [Troubleshoot Android VpnService DNS Filtering](how-to/troubleshoot-vpn.md)
- [Troubleshoot macOS Permissions](how-to/troubleshoot-permissions.md)
- [Recover or Unenroll a Device](how-to/recover-device.md)

### 4. 🏛️ [Architecture](architecture/overview.md)
Detailed technical explanations of system topologies, protocols, and mechanisms:
- [Architecture Overview](architecture/overview.md)
- [Distributed System Architecture](architecture/system-architecture.md)
- [Data Flow & Synchronization](architecture/data-flow.md)
- [Consent-Based Device Enrollment Protocol](architecture/device-enrollment.md)
- [Policy Engine & Precedence Matrix](architecture/policy-engine.md)
- [Offline-First State Machine](architecture/offline-first.md)
- [Android Network Engine & RFC 1035 Parser](architecture/android-network-engine.md)
- [macOS ManagedSettings & Collector Daemon](architecture/macos-enforcement.md)
- [Security Architecture](architecture/security-architecture.md)

### 5. 📑 [Reference](reference/api.md)
Complete, machine-accurate specifications of all interfaces and formats:
- [REST API Reference](reference/api.md)
- [Authentication & JWT Specifications](reference/authentication.md)
- [Policy Schema & Target Types](reference/policies.md)
- [Device Model & States](reference/devices.md)
- [WebSocket Real-Time Event Protocol](reference/events.md)
- [Database Schema DDL & Relational Map](reference/database.md)
- [Environment Configuration Reference](reference/configuration.md)

### 6. 💡 [Concepts](concepts/policies.md)
Foundational theory and domain models underpinning the platform:
- [Policy & Rule Fundamentals](concepts/policies.md)
- [Native OS Enforcement Mechanisms](concepts/enforcement.md)
- [Device Trust & Consent Model](concepts/device-trust.md)
- [Distributed Attention Budgets](concepts/attention-budget.md)
- [Subdomain Matching & Filtering Theory](concepts/domain-filtering.md)
- [Data Minimization & Privacy Model](concepts/privacy-model.md)

### 7. 🔒 [Security](security/threat-model.md) & 🛡️ [Privacy](privacy/data-model.md)
- [Threat Model & Attack Surface Analysis](security/threat-model.md)
- [Security Model & Authorization](security/security-model.md)
- [Idempotent Remote Command Security](security/command-security.md)
- [Data Retention & User Ownership](privacy/data-retention.md)

### 8. ⚙️ [Operations](operations/deployment.md) & 🧪 [Testing](testing/strategy.md)
- [Deployment Guide (Docker, Systemd, Reverse Proxy)](operations/deployment.md)
- [Logging & Monitoring](operations/logging.md)
- [Comprehensive Testing Strategy](testing/strategy.md)
- [Network & DNS Packet Testing](testing/network-testing.md)

### 9. 📋 [Architectural Decision Records (ADRs)](decisions/0001-documentation.md)
- [ADR 0001: Adoption of Diátaxis Documentation Framework](decisions/0001-documentation.md)
- [ADR 0002: Dual-Engine SQLite/PostgreSQL Architecture](decisions/0002-backend.md)
- [ADR 0003: Offline-First Policy Caching and Delta Reconciliation](decisions/0003-offline-first.md)
- [ADR 0004: 6-Tier Deterministic Policy Precedence Engine](decisions/0004-policy-engine.md)
- [ADR 0005: Local RFC 1035 DNS Sinkhole for Android Network Filtering](decisions/0005-android-vpn.md)
- [ADR 0006: Consent-Based Device Enrollment via 6-Character Cryptographic TTL Tokens](decisions/0006-device-enrollment.md)

### 10. 🎓 [Project & Academic](project/scope.md)
- [Project Scope & Deliverables](project/scope.md)
- [Functional & Non-Functional Requirements](project/requirements.md)
- [Roadmap & Future Platform Milestones](project/roadmap.md)
- [Engineering Team & Academic Context](project/team.md)
- [Live Evaluation & Demo Script](project/demo-script.md)
- [Technical Limitations & Boundary Conditions](project/limitations.md)
