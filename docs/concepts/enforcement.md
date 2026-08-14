# Concept: Native OS Enforcement Mechanisms

FocusGuard rejects fragile, hacky enforcement mechanisms (such as editing `/etc/hosts` or installing kernel extensions) in favor of **official, documented platform frameworks**.

---

## 1. Why `/etc/hosts` and Browser Extensions Fail

- **/etc/hosts Editing**: Requires root privileges, fails to block modern apps using hardcoded DNS over TLS/HTTPS, and causes systemwide network breakage if an entry is corrupted.
- **Browser Extensions**: Easily disabled by users, bypassed via Incognito/Private windows or alternate browsers, and completely ineffective against standalone native desktop apps.

---

## 2. The FocusGuard Approach

| Platform | Primary Enforcement Layer | Secondary Protection Layer |
|---|---|---|
| **macOS** | `ManagedSettingsStore` (Out-of-process Apple Screen Time system shields) | `FamilyControls` authorization & Monotonic clock drift watchdog |
| **Android** | `VpnService` Local RFC 1035 UDP DNS Sinkhole (`NXDOMAIN`) | `UsageStatsManager` foreground session tracker & Lockout Activity overlay |
