# FocusGuard Device Authentication & Credentials

## 1. Overview
FocusGuard Phase 2 distinguishes strictly between **User Identity** (account owners, parents, team leads) and **Device Identity** (enrolled laptops, smartphones, browser extensions).

## 2. Token Architecture & Claims Separation

### 2.1 User Tokens
- **Role**: `OWNER` / `USER`
- **Subject (`sub`)**: User UUID
- **Duration**: 1 hour access token + rotating 30-day refresh token in `user_sessions`.
- **Permissions**: Can manage policies, enroll devices, approve/reject pairing, revoke devices, and access analytics.

### 2.2 Device Credential Tokens
- **Role**: `DEVICE`
- **Subject (`sub`)**: Device UUID
- **DeviceID (`device_id`)**: Device UUID
- **UserID (`user_id`)**: Owner UUID (for resource scoping)
- **CredentialVersion (`cred_version`)**: Matches `device_credentials.credential_version`
- **Duration**: 30 days persistent credential
- **Permissions**: Send heartbeats, sync scoped policies, ingest telemetry/blocked events. CANNOT manage other devices or modify policies.

## 3. Revocation Enforcement
Whenever an incoming request reaches `DeviceAuthMiddleware` or `DeviceOrUserAuthMiddleware`:
1. The token signature, expiry, and `Role == "DEVICE"` are validated.
2. The database is checked for device status:
   - If `status == 'REVOKED'`, the request is immediately rejected with `HTTP 403 Forbidden` (`DEVICE_REVOKED`).
   - If `cred_version < current_db_version`, the request is rejected with `HTTP 401 Unauthorized` (`AUTH_REVOKED`).
3. Revocation is permanent. Revoked devices cannot self-reactivate or re-pair without a fresh owner pairing session.

## 4. Platform-Specific Credential Storage
To prevent secrets from leaking:
- **macOS Agent**: Native Keychain Services (`kSecClassGenericPassword`).
- **Windows Agent**: Windows Credential Manager / DPAPI (`CryptProtectData`).
- **Android App**: Android Keystore System (`EncryptedSharedPreferences`).
- **Browser Extension**: `chrome.storage.local` (isolated from web pages and DOM scripts).
- **Node.js Test Client**: `.focusguard-device-credentials.json` with `0600` file permissions.
