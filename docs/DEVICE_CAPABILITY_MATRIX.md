# FocusGuard Device Capability Matrix & Negotiation Architecture

**Document ID**: `FG-CAP-006`  
**Version**: `1.0.0-PROD`  
**Date**: September 7, 2026  
**Status**: APPROVED SPECIFICATION  

---

## 1. Executive Summary & Core Principle

In a distributed multi-device fleet spanning desktop, mobile, and browser environments:
> **The server must NEVER issue an impossible enforcement command to an endpoint.**

Different operating systems enforce security and isolation boundaries differently. A browser extension cannot kill a Windows native process; a desktop background daemon cannot natively intercept encrypted mobile cellular DNS without a local VPN. 

FocusGuard enforces **Deterministic Capability Negotiation**:
1. Clients explicitly declare their capabilities during pairing and heartbeat.
2. The Policy Orchestrator checks each target device's capability set before dispatching policy updates or focus commands.
3. If an endpoint cannot enforce a requested action, the system reports the capability limitation transparently rather than falsely displaying "Blocked Everywhere".

---

## 2. Platform Capability Matrix

| Capability Flag | Browser Extension | Windows Client | macOS Client | Android Client |
| :--- | :---: | :---: | :---: | :---: |
| `USAGE_TRACKING` | ✅ Active Tabs (`tabs`, `webNavigation`) | ✅ Foreground Window (`GetForegroundWindow`) | ✅ Frontmost Application (`NSWorkspace`) | ✅ App Usage (`UsageStatsManager`) |
| `APP_RESTRICTION` | ❌ Not Supported | ✅ Safe Process Interception | ✅ Safe Application Quit / Warning | ✅ Overlay / Accessibility Guard |
| `DOMAIN_BLOCKING` | ✅ Line-Rate (`declarativeNetRequest`) | ⚠️ Browser Extension Coordination | ⚠️ Browser Extension Coordination | ✅ Local RFC 1035 DNS Sinkhole (`VpnService`) |
| `OFFLINE_POLICY` | ✅ `chrome.storage.local` / IndexedDB | ✅ SQLite WAL (`focusguard_client.db`) | ✅ SQLite WAL (`focusguard_macos.db`) | ✅ Room SQLite Database |
| `REALTIME_SYNC` | ✅ WebSocket via Service Worker | ✅ Duplex WebSocket Client | ✅ Duplex WebSocket Client | ✅ Duplex WebSocket Client |
| `DEVICE_GROUP_CONTROL` | ✅ Group Sync Recipient | ✅ Group Sync Recipient | ✅ Group Sync Recipient | ✅ Group Sync Recipient |
| `NOTIFICATION_ENFORCEMENT`| ⚠️ Chrome Notifications API | ✅ Windows Notification Toast API | ✅ Apple `UserNotifications` Framework | ✅ Android Notification Channels |
| `MANAGED_MODE` | ❌ Not Supported | ✅ Single Instance Kiosk Lock | ✅ Active Attention Guard | ✅ Device Admin / Kiosk Pinning |

---

## 3. Detailed Platform Enforcement Primitives

### 3.1 Browser Extension (`apps/extension/`)
- **Strengths**: Zero latency network blocking via Google Chrome/Brave/Edge `declarativeNetRequest` rules. Web usage tracking down to tab switch boundaries.
- **Boundaries**: Strictly sandboxed inside the browser process. Cannot inspect or restrict desktop applications (`discord.exe`, `Spotify.app`).
- **Target Handling**: Automatically filters for `TargetType == "WEBSITE"` or `TargetType == "DOMAIN"`. Silently ignores `TargetType == "APP"`.

### 3.2 Windows Native Client (`apps/windows/`)
- **Strengths**: Win32 subsystem control. Queries `GetForegroundWindow` $\to$ `GetWindowThreadProcessId` $\to$ `QueryFullProcessImageNameW`.
- **Protected Safety Denylist**: System processes unconditionally protected:
  `explorer.exe`, `csrss.exe`, `services.exe`, `wininit.exe`, `winlogon.exe`, `smss.exe`, `lsass.exe`.
- **Target Handling**: Normalizes process names (e.g. `discord.exe`, `C:\Users\...\Discord.exe`). Enforces app restrictions via safe process close or attention warning overlay.

### 3.3 macOS Native Client (`apps/macos/`)
- **Strengths**: Clean Architecture AppKit integration. Tracks `NSWorkspace.shared.frontmostApplication` and idle time via `CGEventSourceSecondsSinceLastEventType`.
- **Protected Safety Denylist**: Apple system apps unconditionally protected:
  `com.apple.finder`, `com.apple.loginwindow`, `com.apple.systempreferences`, `com.apple.systemsettings`, `com.apple.dock`, `com.apple.ActivityMonitor`.
- **Target Handling**: Normalizes targets to Apple **Bundle Identifier** (e.g. `com.hnc.Discord`, `com.spotify.client`). Maps generic names via cross-platform bundle alias table.

### 3.4 Android Client (`apps/android/`)
- **Strengths**: Proof B verifies local `VpnService` implementing RFC 1035 UDP DNS packet parser. Returns `NXDOMAIN` (0.0.0.0) for blocked domains without sending traffic off-device.
- **Boundaries**: Android 10+ restricts background process termination. Enforces attention limits via `SYSTEM_ALERT_WINDOW` warning overlay or Accessibility service redirection.
- **Target Handling**: Matches Android package names (e.g. `com.google.android.youtube`, `com.instagram.android`).

---

## 4. Capability Negotiation Workflow

```
   ┌──────────────────┐
   │  Policy Created  │ (Target: youtube.com + discord.exe)
   └────────┬─────────┘
            │
            ▼
   ┌──────────────────┐
   │ Target Resolution│
   └────────┬─────────┘
            ├────────────────────────────────────────┬────────────────────────────────────────┐
            ▼                                        ▼                                        ▼
   ┌──────────────────┐                     ┌──────────────────┐                     ┌──────────────────┐
   │ Browser Extension│                     │  Windows Agent   │                     │  Android Agent   │
   └────────┬─────────┘                     └────────┬─────────┘                     └────────┬─────────┘
            │ Capability Check                       │ Capability Check                       │ Capability Check
            ▼                                        ▼                                        ▼
   ┌──────────────────┐                     ┌──────────────────┐                     ┌──────────────────┐
   │ Supports DOMAIN  │                     │ Supports APP     │                     │ Supports DOMAIN  │
   │ Applies: youtube │                     │ Applies: discord │                     │ Applies: youtube │
   │ Skips: discord   │                     │ Skips: (ext only)│                     │ Via: DNS Tunnel  │
   └────────┬─────────┘                     └────────┬─────────┘                     └────────┬─────────┘
            │                                        │                                        │
            └────────────────────────────────────────┼────────────────────────────────────────┘
                                                     ▼
                                          ┌──────────────────────┐
                                          │ Dashboard Reporting  │
                                          │ Ext: youtube.com (OK)│
                                          │ Win: discord (OK)    │
                                          │ Android: youtube (OK)│
                                          └──────────────────────┘
```

---

## 5. Failure & Fallback Policy

1. **Unsupported Action**: If a policy targets `APP` and the device only supports `DOMAIN_BLOCKING`, the client acknowledges sync with status `CAPABILITY_FILTERED`, logging an informational event without failing sync.
2. **Degraded State**: If a required permission is revoked (e.g. Android UsageStats disabled by user), the client transitions `protectionState` to `PERMISSION_REQUIRED` and dispatches `TAMPER_ALERT` to the dashboard.
3. **No False Success**: The dashboard displays per-device capability execution badges, showing precisely which targets are actively protected on each platform.
