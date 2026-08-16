# FocusGuard Policy Schema Specification v1

## 1. Policy Object

```json
{
  "id": "pol_abc123",
  "version": 42,
  "name": "YouTube Daily Budget",
  "targetType": "DOMAIN",
  "target": "youtube.com",
  "action": "TIME_LIMIT",
  "limit": 1800,
  "schedule": {
    "days": [1, 2, 3, 4, 5],
    "start": "08:00",
    "end": "22:00"
  },
  "timezone": "UTC",
  "devices": [],
  "priority": 10,
  "isEnabled": true,
  "createdAt": 1723745834000,
  "updatedAt": 1723745834000
}
```

## 2. Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string (UUID) | Yes | Unique policy identifier |
| `version` | number (int) | Yes | Monotonically increasing policy version |
| `name` | string | Yes | Human-readable policy name |
| `targetType` | enum | Yes | Type of target: `APP`, `DOMAIN`, `CATEGORY`, `URL`, `DEVICE`, `DEVICE_GROUP` |
| `target` | string | Yes | The target value (hostname, app bundle, category name) |
| `action` | enum | Yes | Enforcement action: `ALLOW`, `BLOCK`, `TIME_LIMIT`, `SCHEDULE`, `FOCUS`, `NETWORK_BLOCK`, `APP_LIMIT` |
| `limit` | number (seconds) | Conditional | Required when action is `TIME_LIMIT` or `APP_LIMIT`. Total allowed duration per day. |
| `schedule` | object | No | Optional time schedule. If absent, policy is always active. |
| `schedule.days` | number[] | No | ISO weekday numbers (0=Sun, 1=Mon, …, 6=Sat). Empty/absent = all days. |
| `schedule.start` | string (HH:MM) | No | Daily start time in 24h format |
| `schedule.end` | string (HH:MM) | No | Daily end time in 24h format. Can cross midnight (e.g. start=22:00, end=07:00). |
| `timezone` | string (IANA) | No | Timezone for schedule evaluation. Default: "UTC" |
| `devices` | string[] | No | List of `deviceId` values this policy applies to. Empty = all devices. |
| `priority` | number | No | Higher number = evaluated first. Allows ALLOW rules to override BLOCK rules. |
| `isEnabled` | boolean | Yes | Whether this policy is active |

## 3. Action Types

### ALLOW
Explicitly permits access. Useful for creating allowlist overrides above blocking rules.

```json
{
  "action": "ALLOW",
  "target": "kids.youtube.com",
  "priority": 100
}
```

### BLOCK
Unconditionally blocks access to the target, within the optional schedule window.

```json
{
  "action": "BLOCK",
  "target": "tiktok.com"
}
```

### TIME_LIMIT / APP_LIMIT
Permits access until the specified daily budget (in seconds) is exhausted.

```json
{
  "action": "TIME_LIMIT",
  "target": "youtube.com",
  "limit": 1800
}
```

### SCHEDULE
Blocks access only within a scheduled time window.

```json
{
  "action": "SCHEDULE",
  "target": "gaming",
  "targetType": "CATEGORY",
  "schedule": {
    "days": [1, 2, 3, 4, 5],
    "start": "22:00",
    "end": "07:00"
  }
}
```

### FOCUS
Blocks access during an active focus session dispatched by the owner.

```json
{
  "action": "FOCUS",
  "target": "social_media",
  "targetType": "CATEGORY"
}
```

### NETWORK_BLOCK
Blocks at the network layer (Android VPN / Windows firewall / macOS NEFilterDataProvider). Falls back to browser-level enforcement where OS network filtering is unsupported.

## 4. Policy Versioning

All policy changes increment the global policy version atomically:

```
v1 (initial) → v2 (update) → v3 (delete) → ... → v42
```

**Invariants:**
- `version` is always a positive integer.
- Version numbers are monotonically increasing.
- `v42 → v41` is REJECTED by all device policy engines.
- Concurrent updates use optimistic concurrency (the latest write wins in the server).

## 5. Priority Resolution

When multiple policies match the same target, they are resolved in priority order:

```
Priority 100+ : Explicit ALLOW (always wins)
Priority 50   : Time-limited BLOCK
Priority 30   : Category BLOCK
Priority 20   : Focus session BLOCK
Priority 10   : Default BLOCK
```

**Example conflict resolution:**
- Policy A: `BLOCK` `youtube.com`, priority=10
- Policy B: `ALLOW` `kids.youtube.com`, priority=100

Result for `kids.youtube.com`: `ALLOW` (higher priority wins)
Result for `www.youtube.com`: `BLOCK` (only Policy A applies)

## 6. Target Matching Specification

### DOMAIN targets

FocusGuard uses strict hostname-based matching (PSL-aware). A rule for `youtube.com` matches:

| Hostname | Matches? |
|----------|---------|
| `youtube.com` | ✅ Yes (exact) |
| `www.youtube.com` | ✅ Yes (subdomain) |
| `m.youtube.com` | ✅ Yes (subdomain) |
| `music.youtube.com` | ✅ Yes (subdomain) |
| `notyoutube.com` | ❌ No |
| `youtube.com.fake.com` | ❌ No |
| `fakeyoutube.com` | ❌ No |

For multi-level TLDs (e.g. `.co.uk`, `.github.io`), PSL-aware base domain extraction is used to prevent bypass via creative subdomain construction.

### APP targets
Matched by exact bundle/package identifier (e.g. `com.google.android.youtube`).

### CATEGORY targets
Built-in categories: `social_media`, `video_streaming`, `gaming`, `news`, `adult_content`, `shopping`, `education`, `productivity`. Custom categories are supported by the owner.

## 7. Offline Evaluation Contract

A device evaluating a policy offline uses its locally stored policy set. If the server has a newer version (discovered on reconnection), the device downloads and applies it. During the offline period:

- Usage is tracked locally.
- `TIME_LIMIT` decisions use locally accumulated today's usage.
- Block decisions continue without interruption.
- Events are queued for later synchronization.

## 8. Policy Lifecycle States

```
DRAFT → ACTIVE → DISABLED → DELETED
```

Only `ACTIVE` policies are downloaded to devices. `DISABLED` policies remain in storage but are excluded from evaluation.

## 9. Event Schema

Events emitted by policies follow the format defined in [event-schema.md](./event-schema.md).
