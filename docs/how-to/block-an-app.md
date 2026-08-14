# How-To: Block an Application

This guide demonstrates how to restrict an application on macOS (via Bundle ID) or Android (via Package Name).

---

## 1. Finding the Target Identifier

- **macOS Bundle Identifier**:
  Find the bundle identifier using `mdfind` or `defaults`:
  ```bash
  osascript -e 'id of app "Discord"'
  # Output: com.hnc.Discord
  ```
- **Android Package Name**:
  Find package names using ADB or Settings:
  ```bash
  adb shell pm list packages | grep discord
  # Output: package:com.discord
  ```

---

## 2. Creating the Policy via API

Send a `POST` request to `/api/v1/policies`:

```bash
curl -X POST http://localhost:8080/api/v1/policies \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <OWNER_TOKEN>" \
  -d '{
    "name": "Discord Restriction",
    "limitSeconds": 1800,
    "period": "DAILY",
    "enforcementMode": "BLOCK",
    "targets": [
      {
        "targetType": "APP",
        "targetValue": "Discord"
      }
    ],
    "assignedDeviceIds": []
  }'
```

---

## 3. Enforcement Behavior

- **macOS**: `ManagedSettingsStore` attaches an `ApplicationToken` shield. Launching Discord triggers the native Screen Time prompt.
- **Android**: `UsageStatsManager` detects `com.discord` in the foreground. When cumulative usage exceeds 1800 seconds (30 minutes), the FocusGuard lockout activity is rendered.
