# Threat Model & Attack Surface Analysis

This document identifies potential threat vectors against the FocusGuard multi-device platform and describes our countermeasures.

---

## 1. Identified Threat Vectors

### Threat A: Clock Manipulation (Rolling Back System Time)
- **Attack**: User changes the system date backwards to reset daily usage aggregates.
- **Countermeasure**: macOS and Android clients compare wall-clock time against hardware monotonic timers (`CLOCK_MONOTONIC_RAW` / `SystemClock.elapsedRealtime()`). Discrepancies lock active shields until verified with the cloud time source.

### Threat B: DNS Bypass via Encrypted DNS (DoH/DoT)
- **Attack**: User configures a custom DNS-over-HTTPS resolver to bypass local UDP port 53 DNS sinkholing.
- **Countermeasure**: The Android `VpnService` routes all IP traffic to TUN and drops TCP/UDP port 853 (DNS-over-TLS). For supervised child accounts, private DNS settings can be locked via Android `DevicePolicyManager`.

### Threat C: Force-Quitting Application Daemon
- **Attack**: User terminates the FocusGuard process using Activity Monitor or Task Manager.
- **Countermeasure**: On macOS, shields are maintained out-of-process by Apple's `ManagedSettingsStore` daemon. On Android, `VpnService` is maintained by the OS system server.

### Threat D: Replay Attacks on Remote Commands
- **Attack**: Attacker intercepts and replays a `REMOTE_FOCUS_START` packet.
- **Countermeasure**: Commands carry unique UUIDs (`commandId`) and an absolute `expiresAt` timestamp. Expired or duplicate commands are rejected by the device engine.
