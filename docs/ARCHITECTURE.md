# FocusGuard Phase 1 — System Architecture Document
**Status:** Canonical Reference (Phase 1 — Browser Protection Platform)  
**Version:** 1.0.0  
**Target:** Google Chrome (Primary), Brave, Microsoft Edge, Mozilla Firefox (Via BrowserAdapter)

---

## 1. System Architecture Overview

FocusGuard Phase 1 provides an offline-resilient, deterministic website time-limit and blocking platform consisting of:
1. **FocusGuard Cloud Backend (API & Real-time Hub)**: High-performance Go/Chi service supporting PostgreSQL and zero-dependency embedded SQLite, JWT authentication, versioned policy storage, idempotent event batch ingestion, and bi-directional WebSockets.
2. **FocusGuard Browser Extension (MV3)**: Modular WebExtension adhering to Manifest V3, utilizing `declarativeNetRequest` (DNR), `storage.local`, `idle`, `tabs`, `windows`, and `alarms` APIs with a dedicated Browser Adapter abstraction layer.
3. **FocusGuard Web Command Center (Dashboard)**: Centralized management dashboard for defining target domain policies, monitoring real-time active attention usage, and reviewing tamper/enforcement event logs.
4. **Shared Core Domain Packages**: Deterministic TypeScript/JavaScript domain engines for domain normalization (`domain-engine` / `domain-core`), policy evaluation (`policy-core`), cryptographic proofs (`crypto`), event generation (`event-model`), and schema validation (`validation`).

```
                              ┌──────────────────────────────────────────────────────────┐
                              │                 FOCUSGUARD CLOUD BACKEND                 │
                              │  - REST API (/api/v1)                                    │
                              │  - Policy Versioning & Storage                           │
                              │  - Idempotent Event Ingestion (/events/batch)            │
                              │  - Realtime Hub (WebSocket /ws)                          │
                              │  - PostgreSQL / Embedded SQLite Engine                   │
                              └───────────────────────────┬──────────────────────────────┘
                                                          │
                                     HTTPS REST Sync & WSS Broadcast
                                                          │
          ┌───────────────────────────────────────────────┴──────────────────────────────────────────────┐
          │                                                                                              │
          ▼                                                                                              ▼
┌───────────────────────────────────────────────┐                              ┌───────────────────────────────────────────────┐
│        FOCUSGUARD BROWSER EXTENSION (MV3)     │                              │         FOCUSGUARD WEB DASHBOARD              │
│                                               │                              │                                               │
│  ┌─────────────────────────────────────────┐  │                              │  - Policy Definition (youtube.com, 30s)       │
│  │   Background Service Worker / Engine    │  │                              │  - Real-time Attention Analytics              │
│  │  - UsageEngine (Active / Idle / Focus)  │  │                              │  - Live Enforcement Feed                      │
│  │  - PolicySync (Incremental / Offline)   │  │                              │  - Fleet & Device Management                  │
│  │  - PolicyEngine (Deterministic budget)  │  │                              │  - Diagnostics & Health Status                │
│  │  - DNR RuleCompiler (Native 0ms block)  │  │                              └───────────────────────────────────────────────┘
│  │  - Persistent EventQueue (Offline FIFO) │  │
│  └────────────────────┬────────────────────┘  │
│                       │                       │
│  ┌────────────────────┴────────────────────┐  │
│  │         Browser Adapter Layer           │  │
│  │  (Chrome, Brave, Edge, Firefox Compat)  │  │
│  └────────────────────┬────────────────────┘  │
│                       │                       │
│  ┌────────────────────┴────────────────────┐  │
│  │         User-Facing UI Components       │  │
│  │  - Premium Block Page (/pages/block.html│  │
│  │  - Quick Status Popup (/popup)          │  │
│  │  - Advanced Options & Diagnostics       │  │
│  └─────────────────────────────────────────┘  │
└───────────────────────────────────────────────┘
```

---

## 2. Component Boundaries & Responsibilities

### A. Shared Core Packages (`packages/`)
* **`domain-core` / `domain-engine`**: Pure domain module. Implements Public Suffix List (PSL) multi-level parsing, domain normalization (lowercase, trim trailing dots, port stripping, punycode/IDN), registrable domain extraction, and strict non-substring matching. Strictly rejects `url.includes()`.
* **`policy-core`**: Pure deterministic domain evaluator. Zero dependencies on DOM, browser APIs, or database. Evaluates policies with clear precedence (Explicit BLOCK > Time Limit Exhausted > Explicit ALLOW > Default Allow).
* **`event-core` / `event-model`**: Structured, typed event factory for all telemetry events (`USAGE_SESSION_STARTED`, `USAGE_SESSION_ENDED`, `LIMIT_REACHED`, `DOMAIN_BLOCKED`, `POLICY_APPLIED`, `SYNC_FAILED`, `SYNC_RECOVERED`).
* **`validation`**: Zod / schema-backed assertion and validation contracts ensuring zero untrusted inputs enter backend or extension state.

### B. Cloud Backend Service (`backend/`)
* **REST Handlers**: Validates request contracts, enforces JWT authentication, handles device enrollment, manages versioned policies, and ingests batch events with UUID deduplication.
* **WebSocket Hub**: Broadcasts real-time events (`POLICY_UPDATED`, `LIMIT_REACHED`, `FOCUS_SESSION_STARTED`) to connected clients while maintaining ping/pong heartbeat health checks.
* **Data Persistence**: Relational schema running against PostgreSQL in production cluster or pure Go SQLite in zero-dependency local environments.

### C. Browser Extension (`apps/extension/`)
* **`background/service-worker.js`**: Central orchestration bus.
* **`core/session-tracker.js` (Usage Engine)**: State machine tracking active attention only. Listens to `chrome.tabs.onActivated`, `chrome.tabs.onUpdated`, `chrome.windows.onFocusChanged`, and `chrome.idle.onStateChanged`. Calculates elapsed time via injected Clock abstraction (`now() - lastTimestamp`).
* **`storage/policy-cache.js`**: Persists policies, policy version, today's aggregated usage, device identity, and offline event queue in `chrome.storage.local`.
* **`core/dnr-compiler.js` (Rule Compiler)**: Compiles active block policies into deterministic `declarativeNetRequest` rules with collision-free rule IDs.
* **`pages/block.html` & `block.js`**: Minimalist, calm, accessible, dark-mode/light-mode block page displaying exact policy rationale, elapsed usage, reset time, and navigation controls.

---

## 3. Data Flow

### Policy Lifecycle Flow
1. **Creation**: User configures policy on Dashboard (Target: `youtube.com`, Daily Limit: 30s).
2. **Validation & Versioning**: Backend validates target domain and positive limit seconds, saves to database, and increments user policy version ($V_{n+1}$).
3. **Propagation**: 
   - Real-time: WebSocket broadcasts `{ type: "POLICY_UPDATED", version: Vn+1 }`.
   - Polling / On-Connect: Extension queries `GET /api/v1/policies` on boot, network recovery, or periodic alarm.
4. **Local Atomic Activation**:
   - Extension downloads payload.
   - Validates payload against `ValidationEngine`.
   - Compiles declarativeNetRequest dynamic rules.
   - Persists to `chrome.storage.local`.
   - Activates in `ExtensionPolicyEngine`.
   - If validation or compilation fails, previous active policy remains untouched.

---

## 4. Event Flow & Active Usage Accounting

```
Active Window Focused + Tab Active + User Not Idle
                     │
                     ▼
             [STARTED / RESUMED]
                     │
         Elapsed Time = Now - PrevTimestamp
                     │
         ┌───────────┴───────────┐
         ▼                       ▼
    [User Leaves Tab]     [Budget Exhausted (30s)]
         │                       │
         ▼                       ▼
      [PAUSED]             [LIMIT_REACHED]
                                 │
                   ┌─────────────┴─────────────┐
                   ▼                           ▼
            Activate DNR Rule          Enqueue DOMAIN_BLOCKED
                   │                           │
                   ▼                           ▼
           Redirect to Block Page       POST /events/batch
                                               │
                                               ▼
                                      Dashboard Updates
```

### Non-Negotiable Active Usage Rule
Time is accumulated if and only if:
1. Window is focused (`windowId !== WINDOW_ID_NONE`).
2. Tab is active within the focused window.
3. User is active (`chrome.idle.queryState === 'active'`).
4. Protocol is HTTP/HTTPS and domain is trackable (not browser internal `chrome://`, `about:`, `file://`).

---

## 5. Security Boundaries

1. **Zero Secret Exposure**: No long-lived master API keys or secrets embedded in extension bundles. Extensions authenticate using user-authenticated short-lived JWT tokens stored exclusively in `chrome.storage.local`.
2. **Strict Domain Matching**: Uses strict hostname and PSL registrable domain matching. Attacker domains like `youtube.com.evil.com` are strictly parsed as `evil.com` and will never match `youtube.com`.
3. **No Trust of Client Input**: Backend validates all payloads, timestamps, durations, and UUIDs via Zod/Go-validators before database persistence.
4. **Tamper & Audit Logging**: Any unauthorized rule tampering, token mismatch, or clock skew triggers an audit log in `audit_logs` and an enforcement event.

---

## 6. Offline Behavior & Network Recovery

1. **Local-First Enforcement**: All policy decisions (`ALLOW` vs `BLOCK`) are evaluated entirely in-memory inside the browser extension. Zero round-trips to backend on navigation.
2. **Restart Survival**: Current daily usage counters and active sessions are flushed to `chrome.storage.local`. On browser restart, unclosed sessions are safely finalized without double counting.
3. **Offline Event Queue**: Enforcement and session events are queued in a persistent, bounded FIFO queue in `chrome.storage.local`.
4. **Network Reconnection**: Upon network restoration (`navigator.onLine` or successful REST probe), the queue drains via idempotent `POST /api/v1/events/batch` with server-side UUID deduplication.

---

## 7. Browser Compatibility Plan

| Browser | Manifest Version | Network Interception | Storage Layer | Idle Detection | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Google Chrome** | MV3 | `declarativeNetRequest` | `chrome.storage.local` | `chrome.idle` (60s) | Primary (Target) |
| **Brave Browser** | MV3 | `declarativeNetRequest` | `chrome.storage.local` | `chrome.idle` (60s) | 100% Compatible |
| **Microsoft Edge** | MV3 | `declarativeNetRequest` | `chrome.storage.local` | `chrome.idle` (60s) | 100% Compatible |
| **Mozilla Firefox** | MV3 / MV2 polyfill | `declarativeNetRequest` / `webRequest` | `browser.storage.local` | `browser.idle` | Adapter Compatible |

### BrowserAdapter Interface Abstraction
```typescript
export interface BrowserAdapter {
  getActiveTab(): Promise<{ id: number; url: string; windowId: number } | null>;
  isWindowFocused(windowId: number): Promise<boolean>;
  getIdleState(thresholdSeconds: number): Promise<'active' | 'idle' | 'locked'>;
  updateDynamicRules(options: { addRules?: any[]; removeRuleIds?: number[] }): Promise<void>;
  getStorage<T>(key: string): Promise<T | null>;
  setStorage<T>(key: string, value: T): Promise<void>;
  redirectTab(tabId: number, targetUrl: string): Promise<void>;
}
```
All browser-specific APIs are called strictly through the `BrowserAdapter` interface, avoiding vendor lock-in and enabling automated testing with mock adapters.
