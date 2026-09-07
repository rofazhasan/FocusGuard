# FocusGuard Phase 3 Windows Architecture Specification

**Document ID**: FG-ARCH-003  
**Version**: 3.0.0-PROD  
**Status**: APPROVED ARCHITECTURE  
**Target Platform**: Windows 10 & 11 (x86_64, ARM64)  
**Implementation**: Native Rust Core (`src-tauri/`) with Tauri UI (`src/`)

---

## 1. System Architecture Overview

The FocusGuard Windows Native Client uses a clean-architecture layered model that completely isolates platform-specific Win32 primitives, local SQLite persistence, and network protocols from pure domain rules (policy evaluation, active usage state transitions, and budget calculations).

```
┌────────────────────────────────────────────────────────────────────────┐
│                              TAURI UI                                  │
│                                                                        │
│  [ Dashboard ]   [ Applications ]   [ Policies ]   [ Usage Analytics ] │
│  [ Devices ]     [ Settings ]       [ Diagnostics ]                    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    │ Tauri IPC (Commands & Events)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                              RUST CORE                                 │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                     APPLICATION LAYER                            │  │
│  │  DeviceService        PolicyService        UsageService          │  │
│  │  TimerService         SyncService          EnforcementService    │  │
│  └────────────────────────────────┬─────────────────────────────────┘  │
│                                   │                                    │
│                                   ▼                                    │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                       DOMAIN LAYER                               │  │
│  │  DeviceIdentity       Policy & Target      UsageSession & State  │  │
│  │  PolicyEngine         EnforcementDecision  FocusGuardEvents      │  │
│  └────────────────────────────────┬─────────────────────────────────┘  │
│                                   │                                    │
│                                   ▼                                    │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                   INFRASTRUCTURE & ADAPTERS                      │  │
│  │  Win32 Foreground     Win32 Idle/Lock      Process Controller    │  │
│  │  SQLite Database      DPAPI Secure Store   FocusGuard API Client │  │
│  │  WebSocket Gateway    System Tray Adapter  Windows Notifications │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
             ┌──────────────────────┴──────────────────────┐
             ▼                                             ▼
┌─────────────────────────┐                   ┌─────────────────────────┐
│     WINDOWS SYSTEM      │                   │   FOCUSGUARD BACKEND    │
│  GetForegroundWindow    │                   │  HTTPS REST API (v1)    │
│  Process Image Query    │                   │  WSS Realtime Hub       │
│  GetLastInputInfo       │                   │  Policy & Event Sync    │
│  DPAPI CryptProtect     │                   │  Device Revocation      │
└─────────────────────────┘                   └─────────────────────────┘
```

---

## 2. Directory & Component Structure

The client codebase is housed in `apps/windows/` adhering to strict domain-driven hexagonal boundaries:

```
apps/windows/
├── Cargo.toml                         # Cargo workspace configuration
├── package.json                       # Tauri frontend dependencies
├── tauri.conf.json                    # Tauri build & permissions config
├── src-tauri/
│   ├── Cargo.toml                     # Rust core dependencies
│   └── src/
│       ├── main.rs                    # Tauri desktop bootstrap & tray setup
│       ├── lib.rs                     # Shared library interface for testing
│       ├── app/
│       │   ├── commands.rs            # Tauri IPC command definitions
│       │   └── state.rs               # Thread-safe managed application state
│       ├── domain/
│       │   ├── device.rs              # Device enrollment, state machine, keys
│       │   ├── policy.rs              # Policy definitions, limits, schedules
│       │   ├── usage.rs               # Target identity, session, tracking states
│       │   ├── enforcement.rs         # Enforcement actions, process denylist
│       │   └── events.rs              # FocusGuard canonical event envelopes
│       ├── application/
│       │   ├── device_service.rs      # Pairing orchestration & credential init
│       │   ├── policy_service.rs      # Local cache & deterministic evaluation
│       │   ├── usage_service.rs       # Active window usage state machine
│       │   ├── timer_service.rs       # Monotonic clock ticks & checkpointing
│       │   ├── sync_service.rs        # Heartbeat, policy pull, delta push
│       │   └── enforcement_service.rs # Notification & safe process termination
│       ├── infrastructure/
│       │   ├── windows/               # Native Win32 API adapters
│       │   │   ├── foreground.rs      # GetForegroundWindow & PID resolver
│       │   │   ├── idle.rs            # GetLastInputInfo & lock detection
│       │   │   └── process.rs         # Safe termination & denylist check
│       │   ├── database/              # Embedded SQLite WAL engine
│       │   │   ├── schema.rs          # Table creation and indexing
│       │   │   └── migrations.rs      # Versioned database migrations
│       │   ├── secure_storage/        # DPAPI credential protection
│       │   │   └── dpapi.rs           # Windows CryptProtectData binding
│       │   └── api/                   # FocusGuard Cloud HTTP & WS client
│       │       ├── client.rs          # REST client (reqwest / hyper)
│       │       └── websocket.rs       # Async WebSocket client (tokio-tungstenite)
│       ├── adapters/
│       │   └── repositories/          # SQLite repository implementations
│       └── tests/                     # Unit, integration, and recovery tests
├── src/                               # Frontend UI (TypeScript / CSS)
│   ├── index.html                     # Single-page application root
│   ├── styles/                        # Dark-mode modern design tokens
│   ├── pages/                         # Dashboard, Apps, Policies, Usage, Settings
│   └── services/                      # Tauri IPC invocation wrapper
└── docs/                              # Architecture, QA, Security, Build reports
```

---

## 3. Core Subsystems

### 3.1 Foreground Window & Process Resolver
To prevent measuring background daemons or hidden windows:
1. `ForegroundAppProvider` calls Win32 `GetForegroundWindow()`.
2. Resolves thread and PID via `GetWindowThreadProcessId()`.
3. Queries full process executable path via `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, ...)` followed by `QueryFullProcessImageNameW()`.
4. Extracts and normalizes the base executable name (e.g., `discord.exe`, `chrome.exe`).
5. Inspects window title via `GetWindowTextW()` where helpful for context.
6. Returns canonical `ForegroundAppInfo { pid, executable_name, executable_path, window_title, timestamp }`.

### 3.2 Active Usage State Machine & Monotonic Timer
Usage counts **only** when all of the following conditions are simultaneously met:
- A tracked application matches the foreground executable name or path.
- The user session is active (Windows is not locked, screensaver is not active).
- User idle duration (calculated via `GetLastInputInfo()`) is below the threshold (default: 60 seconds).
- The system is not suspended or in low-power sleep.

```
┌──────────────┐
│  NO_TARGET   │◄────────────────────────────────┐
└──────┬───────┘                                 │
       │ Tracked app brought to foreground       │
       ▼                                         │
┌──────────────┐                                 │
│START_SESSION │                                 │
└──────┬───────┘                                 │
       │ Monotonic tick (1s checkpoint)          │ Window switched,
       ▼                                         │ idle >= 60s, or
┌──────────────┐                                 │ workstation locked
│   TRACKING   ├─────────────────────────────────┘
└──────┬───────┘
       │ Policy limit reached
       ▼
┌──────────────┐
│  RESTRICTED  │ ──► Triggers safe enforcement (Notify / Close App)
└──────────────┘
```

### 3.3 Safe Enforcement & Protected Process Denylist
FocusGuard unconditionally protects vital operating system and system stability processes. The following processes are hardcoded into an immutable denylist:
- `System`, `Registry`, `smss.exe`, `csrss.exe`, `wininit.exe`, `winlogon.exe`, `services.exe`, `lsass.exe`, `fontdrvhost.exe`, `dwm.exe`, `spoolsv.exe`, `explorer.exe`.

If a user policy attempts to target a denylisted executable:
1. The policy engine refuses enforcement.
2. An audit log `ENFORCEMENT_REFUSED_DENYLIST` is emitted.
3. The client refuses process closure.

For valid targets configured with `CLOSE_APPLICATION`:
1. FocusGuard posts `WM_CLOSE` to top-level windows of the target PID for clean termination.
2. Waits a 3-second grace period.
3. If the process does not terminate and policy requires it, issues `TerminateProcess()`.
4. Emits `ENFORCEMENT_TRIGGERED` event.

### 3.4 Local SQLite Database & Offline Event Queue
The local database uses SQLite in WAL mode with the following schema:
- `device_state`: Stores local device UUID, status (`UNREGISTERED`, `PAIRING`, `ACTIVE`, `REVOKED`), friendly name, and policy version.
- `cached_policies`: Locally synced policies with version, daily limit, warning threshold, and target values.
- `usage_sessions`: Active and historical sessions with start time, end time, checkpoint timestamp, and duration seconds.
- `daily_usage`: Aggregated daily total seconds per target per date.
- `pending_events`: Queue of events (`USAGE_SESSION_STARTED`, `LIMIT_REACHED`, `ENFORCEMENT_TRIGGERED`) marked `PENDING`. Upon successful backend sync, transitioned to `SYNCED`.
- `sync_state`: Monotonic sync cursor and timestamps.

### 3.5 Secure Credential Storage
Device authentication requires persistent possession of the 30-day `deviceToken`.
- **Windows Implementation**: Utilizes Windows Data Protection API (`DPAPI` via `CryptProtectData` with user-scope entropy).
- **Cross-Platform Abstraction**: Software AES-256-GCM encrypted store for headless testing on non-Windows host environments.
- **Zero-Trust Revocation**: When revoked, the credential file/DPAPI blob is immediately overwritten with zeros and unlinked.

---

## 4. Crash Recovery & Downtime Invariant
If the FocusGuard application crashes or the PC loses power:
1. On restart, the `TimerService` scans `usage_sessions` for any session with `ended_at IS NULL`.
2. It reads `last_checkpoint_at` (updated once per second during tracking).
3. The session is closed with `ended_at = last_checkpoint_at`.
4. **Downtime is never counted**: The hours between the crash and subsequent restart are completely excluded from the application budget.

---

## 5. Multiple Instance Prevention
FocusGuard uses a named Win32 mutex (`Global\FocusGuard_Windows_SingleInstance_Mutex`).
- First instance: Acquires mutex and proceeds with initialization.
- Second instance: Detects existing mutex, sends a custom IPC message or focuses the existing window via `FindWindowW` / `SetForegroundWindow`, and immediately exits with exit code 0.
- Result: Exactly one tracking engine runs per user session.
