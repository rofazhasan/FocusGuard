# Database Schema Reference

FocusGuard supports a **dual-mode database engine**:
1. **Embedded SQLite** with Write-Ahead Logging (`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;`).
2. **PostgreSQL 14+** for clustered cloud deployments.

---

## Entity Relationship Diagram

```
 users (1) ─────────────◄ (N) devices
   │                             │
   │                             ├─────────────◄ (N) usage_aggregates
   │                             ├─────────────◄ (N) blocked_events
   ├─────────────◄ (N) policies  ├─────────────◄ (N) remote_commands
   │                   │         │
   │                   ├─────────┼─────────────◄ (N) policy_assignments
   │                   └─────────┴─────────────◄ (N) policy_targets
   │
   ├─────────────◄ (N) enrollment_tokens
   └─────────────◄ (N) audit_logs
```

---

## SQL Schema DDL

```sql
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE devices (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_name TEXT NOT NULL,
    platform TEXT NOT NULL,
    os_version TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'PERSONAL',
    is_managed INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'ONLINE',
    policy_version INTEGER NOT NULL DEFAULT 1,
    last_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE enrollment_tokens (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pairing_code TEXT UNIQUE NOT NULL,
    device_name TEXT NOT NULL,
    target_role TEXT NOT NULL DEFAULT 'MANAGED_USER',
    expires_at DATETIME NOT NULL,
    is_claimed INTEGER NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE policies (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    limit_seconds INTEGER NOT NULL,
    period TEXT NOT NULL DEFAULT 'DAILY',
    schedule_cron TEXT,
    timezone TEXT NOT NULL DEFAULT 'UTC',
    enforcement_mode TEXT NOT NULL DEFAULT 'BLOCK',
    is_enabled INTEGER NOT NULL DEFAULT 1,
    version INTEGER NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE policy_targets (
    id TEXT PRIMARY KEY,
    policy_id TEXT NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
    target_type TEXT NOT NULL,
    target_value TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE policy_assignments (
    policy_id TEXT NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    PRIMARY KEY (policy_id, device_id)
);

CREATE TABLE usage_aggregates (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    target_value TEXT NOT NULL,
    date TEXT NOT NULL,
    total_duration_seconds INTEGER NOT NULL DEFAULT 0,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, device_id, target_value, date)
);

CREATE TABLE remote_commands (
    id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    issued_by TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    command_type TEXT NOT NULL,
    payload TEXT NOT NULL,
    issued_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL,
    status TEXT NOT NULL DEFAULT 'PENDING'
);

CREATE TABLE audit_logs (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id TEXT,
    action TEXT NOT NULL,
    details TEXT,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```
