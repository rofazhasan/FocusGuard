# Tutorial: Creating Your First Remote Focus Session

Remote Focus Sessions allow an account owner to dispatch an immediate, timed attention lockdown across all or specific fleet devices.

---

## Learning Objectives
- Understanding the Remote Focus protocol lifecycle.
- Dispatching idempotent commands via `POST /api/v1/commands/dispatch`.
- Observing real-time WebSocket fan-out and local shield activation.
- Concluding sessions gracefully and restoring standard policy state.

---

## Step 1: Selecting Focus Duration & Target Scope

FocusGuard supports predefined focus intervals (15m, 30m, 45m, 60m) or custom durations. During an active focus session:
- **Blocked Fleetwide**: All `SOCIAL`, `VIDEO`, and `GAMING` categories.
- **Explicit Allowlist Override**: Educational resources (e.g. `canvas.university.edu`, `github.com`, `stackoverflow.com`) and essential messaging remain accessible.

---

## Step 2: Dispatching the Focus Command

To trigger a 45-minute focus session on a managed Android tablet:

```bash
curl -X POST http://localhost:8080/api/v1/commands/dispatch \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <OWNER_TOKEN>" \
  -d '{
    "deviceId": "4afd6e70-4e07-4033-ae19-7b8b58752cba",
    "commandType": "REMOTE_FOCUS_START",
    "durationSec": 2700,
    "payload": {
      "durationMinutes": 45,
      "blockedCategories": ["VIDEO", "SOCIAL", "GAMING"],
      "blockedDomains": ["youtube.com", "instagram.com", "reddit.com"]
    }
  }'
```

### JSON Response:
```json
{
  "commandId": "876b3aea-48cd-4bb4-bb62-bfac6a0d0062",
  "deviceId": "4afd6e70-4e07-4033-ae19-7b8b58752cba",
  "commandType": "REMOTE_FOCUS_START",
  "issuedAt": "2026-08-14T17:19:53Z",
  "expiresAt": "2026-08-14T18:04:53Z",
  "status": "DISPATCHED",
  "payload": {
    "durationMinutes": 45,
    "blockedCategories": ["VIDEO", "SOCIAL", "GAMING"],
    "blockedDomains": ["youtube.com", "instagram.com", "reddit.com"]
  }
}
```

---

## Step 3: Local Shield Engagement

When the target device receives the command:
1. It validates the command's cryptographic signature and confirms `expiresAt > NOW()`.
2. On Android, the `VpnService` intercepts DNS lookups for `youtube.com` or `instagram.com` and replies with `NXDOMAIN`.
3. On macOS, `ManagedSettingsStore` activates the application shield overlay.
4. The local focus countdown timer runs autonomously—even if network connectivity is severed during the session.

---

## Step 4: Ending the Session

When the countdown timer expires, or if the Owner ends the session early via `POST /api/v1/focus/end`, the backend emits `FOCUS_ENDED`. Enrolled devices clear temporary emergency shields and revert to standard daily budget evaluations.
