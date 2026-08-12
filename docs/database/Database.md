# FocusGuard Database Design & Schema Reference

## 1. Schema Overview

FocusGuard relies on PostgreSQL for persistent storage of user identities, enrolled devices, policy rules, usage session streams, pre-aggregated analytics, and audit events.

```
+--------------------+       +--------------------+       +-----------------------+
|       users        |       |      devices       |       |  device_sync_states   |
+--------------------+       +--------------------+       +-----------------------+
| id (UUID, PK)      |<------| id (UUID, PK)      |<------| id (UUID, PK)         |
| email (VARCHAR)    |       | user_id (FK)       |       | device_id (FK)        |
| password_hash      |       | device_name        |       | last_synced_at        |
| created_at         |       | platform           |       | client_version        |
| updated_at         |       | os_version         |       | sync_sequence         |
+--------------------+       | status             |       +-----------------------+
          |                  | last_seen_at       |
          |                  +--------------------+
          v                            |
+--------------------+                 |
|      policies      |                 |
+--------------------+                 |
| id (UUID, PK)      |                 |
| user_id (FK)       |                 |
| name               |                 |
| limit_seconds      |                 |
| period             |                 |
| schedule_cron      |                 |
| timezone           |                 |
| enforcement_mode   |                 |
| is_enabled         |                 |
| version (INT)      |                 |
+--------------------+                 |
          |                            |
          +-------------------+        |
          |                   |        |
          v                   v        |
+--------------------+  +--------------------+
|   policy_targets   |  |   policy_devices   |
+--------------------+  +--------------------+
| id (UUID, PK)      |  | policy_id (FK)     |
| policy_id (FK)     |  | device_id (FK)     |
| target_type        |  +--------------------+
| target_value       |
+--------------------+
```

---

## 2. Table Specifications

### `users`
- `id`: `UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `email`: `VARCHAR(255) UNIQUE NOT NULL`
- `password_hash`: `VARCHAR(255) NOT NULL`
- `created_at`: `TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `updated_at`: `TIMESTAMPTZ NOT NULL DEFAULT NOW()`

### `devices`
- `id`: `UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `user_id`: `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE`
- `device_name`: `VARCHAR(100) NOT NULL`
- `platform`: `VARCHAR(20) NOT NULL` -- `MACOS`, `ANDROID`
- `os_version`: `VARCHAR(50) NOT NULL`
- `status`: `VARCHAR(20) NOT NULL DEFAULT 'ONLINE'`
- `last_seen_at`: `TIMESTAMPTZ NOT NULL DEFAULT NOW()`

### `policies`
- `id`: `UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `user_id`: `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE`
- `name`: `VARCHAR(100) NOT NULL`
- `limit_seconds`: `INT NOT NULL DEFAULT 0`
- `period`: `VARCHAR(20) NOT NULL DEFAULT 'DAILY'` -- `DAILY`, `WEEKLY`
- `schedule_cron`: `VARCHAR(100)`
- `timezone`: `VARCHAR(50) NOT NULL DEFAULT 'UTC'`
- `enforcement_mode`: `VARCHAR(30) NOT NULL DEFAULT 'BLOCK'` -- `BLOCK`, `FOCUS_ONLY`, `SCHEDULED_BLOCK`
- `is_enabled`: `BOOLEAN NOT NULL DEFAULT TRUE`
- `version`: `INT NOT NULL DEFAULT 1`

### `usage_aggregates`
- `id`: `UUID PRIMARY KEY DEFAULT gen_random_uuid()`
- `user_id`: `UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE`
- `device_id`: `UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE`
- `target_value`: `VARCHAR(255) NOT NULL`
- `date`: `DATE NOT NULL`
- `total_duration_seconds`: `INT NOT NULL DEFAULT 0`
- `UNIQUE(user_id, device_id, target_value, date)`
