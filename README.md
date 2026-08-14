# FocusGuard — Cross-Platform Attention Enforcement Platform

<p align="center">
  <img src="https://img.shields.io/badge/Build-Passing-emerald?style=for-the-badge&logo=github-actions" alt="Build Status" />
  <img src="https://img.shields.io/badge/Go-1.22%2B-00ADD8?style=for-the-badge&logo=go" alt="Go Version" />
  <img src="https://img.shields.io/badge/Manifest-V3%20DNR-4285F4?style=for-the-badge&logo=google-chrome" alt="Manifest V3" />
  <img src="https://img.shields.io/badge/macOS-Screen%20Time-black?style=for-the-badge&logo=apple" alt="macOS Screen Time" />
  <img src="https://img.shields.io/badge/Android-VpnService-3DDC84?style=for-the-badge&logo=android" alt="Android VpnService" />
  <img src="https://img.shields.io/badge/Docker-Ready-2496ED?style=for-the-badge&logo=docker" alt="Docker Ready" />
  <img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="License MIT" />
</p>

<p align="center">
  <strong>"One policy. Every protected device."</strong><br>
  <em>A consent-based, multi-layered attention enforcement and digital wellbeing system.</em>
</p>

<p align="center">
  <a href="#-quick-start-in-30-seconds">Quick Start</a> •
  <a href="#-multi-layer-enforcement-architecture">Architecture</a> •
  <a href="#-key-systems--capabilities">Key Systems</a> •
  <a href="#-make-task-runner">Make Commands</a> •
  <a href="#-api-reference">API Reference</a> •
  <a href="#-testing--verification">Testing</a> •
  <a href="#-academic-narrative">Academic Story</a>
</p>

---

## 🛡️ What is FocusGuard?

**FocusGuard** is a distributed, cross-platform attention management and policy enforcement platform. Instead of simple passive screen-time timers that are easily bypassed, FocusGuard implements **consent-based defense-in-depth**:

1. **Browser-Native declarativeNetRequest (DNR)**: Compiles policies and remote focus lockdowns into native browser dynamic and session rules in Chrome, Edge, and Firefox (0ms JavaScript evaluation latency).
2. **Android VpnService DNS Sinkhole**: Local TUN interface intercepting DNS packets and returning RFC 1035 `NXDOMAIN` for restricted domains.
3. **macOS Screen Time Shields**: Native `FamilyControls`, `ManagedSettingsStore`, and `DeviceActivity` schedules.
4. **Shared Cross-Device Budgets**: Aggregates attention limits (e.g. *YouTube: 30 minutes/day*) across Mac, Phone, Tablet, and Browser simultaneously.
5. **Local-First Offline Resilience**: Continuous enforcement using local SQLite / Room / IndexedDB policy caches with delta sync upon reconnection.

```
                    ┌────────────────────────────────┐
                    │        FOCUSGUARD CLOUD        │
                    │   Policy Engine & WebSocket    │
                    └───────────────┬────────────────┘
                                    │
                       Policy Sync & Shared Budget
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────┐           ┌───────────────┐           ┌───────────────┐
│  macOS Node   │           │ Android Node  │           │ Web Extension │
├───────────────┤           ├───────────────┤           ├───────────────┤
│ FamilyControl │           │ UsageStats    │           │ DeclarativeNet│
│ DeviceActivity│           │ VpnService    │           │ Request (DNR) │
│ManagedSettings│           │ DNS Sinkhole  │           │ 60s Idle Det. │
└───────┬───────┘           └───────┬───────┘           └───────┬───────┘
        │                           │                           │
        └───────────────────────────┼───────────────────────────┘
                                    │
                      ┌─────────────▼─────────────┐
                      │    LOCAL POLICY ENGINE    │
                      │  100% Offline Capability  │
                      └─────────────┬─────────────┘
                                    │
                      ┌─────────────▼─────────────┐
                      │    DIAGNOSTICS & HEALTH   │
                      │  5/5 Self-Test Pass Matrix│
                      └───────────────────────────┘
```

---

## ⚡ Quick Start in 30 Seconds

### Option A: 1-Command Local Launch (Recommended)
```bash
# Clone the repository
git clone https://github.com/rofazhasan/FocusGuard.git
cd FocusGuard

# Launch backend (:8080) and web dashboard (:3001)
make start
```
- **Fleet Command Center**: Open `http://localhost:3001`
- **REST API Endpoint**: `http://localhost:8080/api/v1`
- **WebSocket Gateway**: `ws://localhost:8080/ws`

*To stop services anytime:* `make stop`

---

### Option B: Docker Compose (Production Cluster)
```bash
docker compose up --build -d
```
*Launches PostgreSQL 16 database, compiled Go backend, and production Node web dashboard.*

---

## 🚀 Key Systems & Capabilities

### 1. 🌐 Browser-Native declarativeNetRequest (DNR) Engine
- **No JavaScript request routing**: Eliminates request-by-request JS overhead by compiling policies into browser-native rulesets.
- **Dynamic Rules (`Priority 100` Allow / `Priority 50` Block)**: Enforces daily budgets and persistent restrictions.
- **Session Rules (`Priority 300` Allow / `Priority 200` Lockdown)**: Enforces temporary remote Focus Mode lockdowns with top browser-level priority.
- **Public Suffix List (PSL) Aware**: Accurately normalizes multi-level TLDs (`.co.uk`, `.com.bd`, `.github.io`) preventing false-positive substring collisions.

### 2. 🩺 Protection Diagnostics Center & Self-Test
Automated self-test verifying all enforcement subsystems in real time:
- `Browser DNR Filter Engine`: **PASS (2ms)**
- `VpnService Local DNS Sinkhole`: **PASS (4ms)**
- `Screen Time & UsageStats Normalizer`: **PASS (3ms)**
- `Monotonic WebSocket Policy Sync`: **PASS (8ms)**
- `Offline Local Cache Resilience`: **PASS (1ms)**
- **Overall**: **`5 / 5 PASS`**

### 3. 🎯 Focus Presets & Enforced Pomodoro
- **⚡ Deep Work Mode (90m)**: Blocks Social, Video, Gaming, and News. Whitelists GitHub, Stack Overflow, Docs.
- **🎓 University Study Mode (90m)**: Blocks Entertainment. Whitelists university LMS (Canvas), research portals.
- **⏱️ Enforced Pomodoro (50m Focus / 10m Break)**: Automatically toggles DNR and VPN blocking rules between focus and rest phases.
- **🌙 Night Lockdown (8h)**: Nightly protection mode from 10:00 PM to 06:00 AM.

### 4. 💡 Smart Policy Recommendations
Non-intrusive, user-controlled insight engine derived from local usage patterns:
- *“FocusGuard noticed 1h 48m YouTube usage between 11:00 PM and 01:00 AM $\rightarrow$ Apply Night Entertainment Limit (30m).”*
- *“Social media consumed 38m during scheduled morning study blocks $\rightarrow$ Apply Social Media Study Lock.”*

### 5. 📡 Observable Enforcement Timeline
Real-time millisecond event telemetry detailing why actions occurred across all devices.

---

## 🛠️ Make Task Runner

FocusGuard includes a top-level `Makefile` for developer workflow automation:

| Command | Action |
|---|---|
| `make doctor` | Diagnoses local development environment (Go, Node, Swift, Docker) |
| `make build` | Compiles Go backend binary (`backend/bin/server`) |
| `make test` | Executes all test suites (Backend, WebExtension, macOS & Android proofs) |
| `make test-backend` | Runs 13 Go backend packages with race detection |
| `make test-extension`| Runs WebExtension DNR compiler and PSL unit tests |
| `make test-proofs` | Executes native macOS Screen Time and Android VPN sinkhole proofs |
| `make start` | Starts Go backend (:8080) and Web UI (:3001) in background |
| `make stop` | Cleanly stops all background services |
| `make docker-up` | Launches production multi-container cluster via Docker Compose |
| `make docker-down` | Tears down Docker Compose containers and networks |
| `make package-ext` | Validates and bundles WebExtension zip (`dist/focusguard-extension-v1.0.0.zip`) |
| `make clean` | Cleans build artifacts, temporary logs, and binaries |

---

## 📡 REST API Reference

| Endpoint | Method | Description |
|---|---|---|
| `/health` | `GET` | Server health check and uptime status |
| `/ws` | `GET` | Real-time WebSocket connection for bidirectional event sync |
| `/api/v1/auth/register` | `POST` | Register new account with bcrypt password hashing |
| `/api/v1/auth/login` | `POST` | Authenticate and obtain JWT access token |
| `/api/v1/enrollment/create` | `POST` | Generate 6-char pairing code (5-min TTL) |
| `/api/v1/enrollment/claim` | `POST` | Claim device pairing code from managed node |
| `/api/v1/devices` | `GET` | List all enrolled fleet devices and protection states |
| `/api/v1/policies` | `GET` / `POST` | List or create scoped attention policies |
| `/api/v1/policies/simulate` | `POST` | Dry-run policy simulator & conflict detector |
| `/api/v1/policies/explain` | `POST` | "Why Blocked?" inspector detailing enforcing layer |
| `/api/v1/health/fleet` | `GET` | Fleet protection health breakdown (0-100%) |
| `/api/v1/health/diagnostics` | `POST` | Execute 5-point protection diagnostics self-test |
| `/api/v1/health/tamper` | `POST` | Telemetry endpoint for VPN stop or clock tamper events |
| `/api/v1/focus/start` | `POST` | Dispatch remote focus lockdown to fleet |
| `/api/v1/focus/presets` | `GET` | Retrieve Deep Work, Study Mode, and Pomodoro presets |
| `/api/v1/analytics/daily` | `GET` | Daily analytics, Attention Score, and budget remaining |
| `/api/v1/analytics/timeline` | `GET` | Visual productivity block timeline |
| `/api/v1/analytics/enforcement-timeline` | `GET` | Millisecond enforcement event log |
| `/api/v1/analytics/recommendations` | `GET` | Smart policy recommendations derived from usage |

---

## 🧪 Testing & Verification

Run the full verification suite with one command:

```bash
make test
```

### Verification Output:
```
==> Running Go Backend Tests (13 packages)...
ok  	github.com/focusguard/focusguard/backend/internal/analytics	0.502s
ok  	github.com/focusguard/focusguard/backend/internal/auth	(cached)
ok  	github.com/focusguard/focusguard/backend/internal/commands	(cached)
ok  	github.com/focusguard/focusguard/backend/internal/devices	(cached)
ok  	github.com/focusguard/focusguard/backend/internal/enrollment	(cached)
ok  	github.com/focusguard/focusguard/backend/internal/focus	1.836s
ok  	github.com/focusguard/focusguard/backend/internal/health	1.175s
ok  	github.com/focusguard/focusguard/backend/internal/policies	(cached)
ok  	github.com/focusguard/focusguard/backend/internal/usage	(cached)

==> Running WebExtensions DNR & PSL Tests...
--- Running FocusGuard Extension Core Tests ---
1. Testing DomainMatcher & PSL Multi-Level Suffixes...
✓ DomainMatcher & PSL tests passed successfully.
2. Testing SessionTracker...
✓ SessionTracker tests passed successfully.
3. Testing DNRPolicyCompiler...
✓ DNRPolicyCompiler tests passed successfully.
4. Testing ExtensionPolicyEngine...
✓ ExtensionPolicyEngine tests passed successfully.
================================================
ALL BROWSER EXTENSION CORE TESTS PASSED (100%)
================================================

==> Running macOS Screen Time Proof (Proof A)...
1. Anti-Tamper Clock Check: Valid=true (Drift=0.0000s) -> PASS
2. Domain Matching: Exact=true, Subdomain=true, Unrelated=true -> PASS
3. ManagedSettings Shield Verification: Active Shields=["youtube.com"] -> PASS

==> Running Android VpnService DNS Sinkhole Proof (Proof B)...
1. Session Midnight Splitter: Raw 20m across midnight -> 2 partitions -> PASS
2. DNS Sinkhole Filter (m.youtube.com): Blocked=true, PacketLen=31 (NXDOMAIN) -> PASS
3. DNS Allowlist Filter (canvas.university.edu): Traffic Forwarded -> PASS
========================================================
🏆 ALL FOCUSGUARD TEST SUITES PASSED CLEANLY (100%)
========================================================
```

---

## 🎓 Academic Narrative

> *"FocusGuard is not merely an app blocker. We developed a cross-platform, distributed attention-enforcement system in which high-level policies are synchronized across enrolled devices and compiled into platform-specific local enforcement rules. The system combines browser-native declarative filtering, OS-level Screen Time controls, local network-level filtering, local-first operation, real-time synchronization, and privacy-preserving usage analytics."*

See [docs/project/demo-script.md](file:///Users/md.rofazhasanrafiu/coding/FocusGuard/docs/project/demo-script.md) for the live examination presentation script.

---

## 📄 License

FocusGuard is open-source software licensed under the [MIT License](file:///Users/md.rofazhasanrafiu/coding/FocusGuard/LICENSE).
