# How-To: Recover or Unenroll a Device

This guide describes the clean unenrollment and emergency recovery procedure for locked devices.

---

## 1. Clean Unenrollment via Owner Dashboard

When a device is decommissioned or removed from the family fleet:
1. Open the **Fleet Command Center** (`http://localhost:3001`).
2. Locate the device under **Enrolled Fleet Devices**.
3. Send a deletion request to unregister the hardware token:
   ```bash
   curl -X DELETE http://localhost:8080/api/v1/devices/<DEVICE_ID> \
     -H "Authorization: Bearer <OWNER_TOKEN>"
   ```
4. The server records a `DEVICE_UNENROLLED` event in the audit ledger and revokes active JWT credentials.

---

## 2. Emergency Local Shield Release

If a device is locked out and cannot contact the backend server:

### macOS
1. Open **Terminal**.
2. Stop the FocusGuard background daemon.
3. Open **System Settings > Screen Time** and authenticate with the macOS administrator account to clear application shields.

### Android
1. Open **Settings > Network & internet > VPN**.
2. Tap the gear icon next to FocusGuard and select **Disconnect VPN**.
3. Launch the Android device in Safe Mode (`Hold Power > Long-press Restart`) to bypass foreground overlay locks if necessary.
