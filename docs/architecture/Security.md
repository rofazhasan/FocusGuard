# FocusGuard Security & Anti-Tamper Specification

## 1. Authentication & Token Management

- **User Password Hashing**: Passwords stored on server using Argon2id / bcrypt with custom salts.
- **JWT Architecture**:
  - **Access Tokens**: Short-lived (15 minutes), signed with RS256 / HS256.
  - **Refresh Tokens**: Long-lived (30 days), stored in database with revocation capabilities.
- **Secure Token Storage**:
  - **macOS**: Stored in **Apple Keychain Services** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
  - **Android**: Stored in **Android Keystore System** via EncryptedSharedPreferences backed by Hardware Security Module (HSM/TEE).

---

## 2. Anti-Tamper & Time Security Engine

To prevent users from changing local device system clock to bypass attention limits:

1. **Monotonic Clock Anchoring**:
   - macOS: `clock_gettime(CLOCK_MONOTONIC_RAW)`
   - Android: `SystemClock.elapsedRealtime()`
   - All session duration deltas are calculated using monotonic ticks, unaffected by manual wall-clock changes.
2. **Server Clock Sync**:
   - Every API request returns `X-Server-Timestamp`.
   - Local engine calculates `Drift = |ServerTimestamp - (LocalWallClock + MonotonicOffset)|`.
   - If `Drift > 120s`, a `CLOCK_TAMPER_DETECTED` event is triggered, local shields lock down, and audit log is uploaded.

---

## 3. Platform Security Boundaries & Compliance

- **macOS Compliance**: FocusGuard strictly utilizes Apple's official `FamilyControls` and `ManagedSettings` frameworks. It does NOT use kernel extensions, stealth daemons, or OS security bypasses.
- **Android Compliance**: FocusGuard utilizes `UsageStatsManager` and a local `VpnService` for DNS-based filtering. The VPN processes traffic 100% locally on device without remote proxying, ensuring full compliance with Google Play Store policies.
- **Data Protection**: Zero logging of user passwords, tokens, or raw unencrypted URL payload contents.
