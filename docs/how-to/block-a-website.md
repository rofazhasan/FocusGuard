# How-To: Block a Website Domain

This guide describes how to target specific web domains and subdomains for attention budgets or total blocking.

---

## 1. Domain Format Rules

When specifying website targets:
- **Do not include protocols**: Use `youtube.com`, not `https://youtube.com`.
- **Do not include paths**: Use `reddit.com`, not `reddit.com/r/popular`.
- **Subdomains are automatically matched**: Specifying `youtube.com` automatically covers:
  - `www.youtube.com`
  - `m.youtube.com`
  - `music.youtube.com`
- **Substring safety**: `youtube.com` will **never** block `notyoutube.com` or `fake-youtube.com`.

---

## 2. Defining the Policy

```bash
curl -X POST http://localhost:8080/api/v1/policies \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <OWNER_TOKEN>" \
  -d '{
    "name": "Social Video Limits",
    "limitSeconds": 1800,
    "period": "DAILY",
    "enforcementMode": "BLOCK",
    "targets": [
      { "targetType": "WEBSITE", "targetValue": "youtube.com" },
      { "targetType": "WEBSITE", "targetValue": "twitch.tv" },
      { "targetType": "WEBSITE", "targetValue": "tiktok.com" }
    ],
    "assignedDeviceIds": []
  }'
```

---

## 3. Platform Enforcement Details

- **Android (`VpnService`)**: When a browser or app resolves `m.youtube.com`, the local DNS parser detects the target domain and responds with `NXDOMAIN` (RCODE 3). The browser displays `"This site can't be reached"`.
- **macOS (`ManagedSettingsStore`)**: Safari and WebKit browsers intercept the request at the OS socket boundary and render the Screen Time web shield.
