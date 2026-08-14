# Technical Limitations & Boundary Conditions

This document transparently documents current system boundaries, edge cases, and platform constraints.

---

## 1. Operating System Boundary Conditions

### macOS
- **WebKit Dependency for Domain Shielding**: Apple's `ManagedSettingsStore.shield.webDomains` operates reliably on Safari and WebKit-based browsers. Non-WebKit browsers (e.g. Firefox) require supplementary application bundle-level blocking or DNS filtering.
- **FamilyControls Entitlement**: Production distribution requires Apple Developer Program membership with the signed `com.apple.developer.family-controls` entitlement.

### Android
- **Single Active VPN Interface**: Android OS restricts devices to one active `VpnService` at a time. Users cannot run FocusGuard's DNS sinkhole simultaneously with third-party commercial VPN tunnels.
- **Custom Private DNS (DoH/DoT)**: If a user manually specifies a custom Private DNS provider in Android settings (overriding system DNS), FocusGuard drops port 853 traffic. In enterprise/family setups, this setting should be locked via MDM or Device Owner profile.

---

## 2. Distributed State Reconciliation
- **Simultaneous Disconnected Usage**: If two devices are disconnected from the internet simultaneously, each device allows up to its local limit before locking. When both devices reconnect, total usage will be reconciled into the database without data loss, but the combined historical duration for that window may exceed the limit retroactively.
