pub const CREATE_TABLES_SQL: &str = r#"
CREATE TABLE IF NOT EXISTS device_state (
    id TEXT PRIMARY KEY,
    device_id TEXT,
    user_id TEXT,
    device_name TEXT NOT NULL,
    platform TEXT NOT NULL,
    client_type TEXT NOT NULL,
    app_version TEXT NOT NULL,
    status TEXT NOT NULL,
    policy_version INTEGER NOT NULL DEFAULT 1,
    public_key_pem TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS cached_policies (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    limit_seconds INTEGER NOT NULL,
    warning_threshold_seconds INTEGER NOT NULL,
    enforcement_action TEXT NOT NULL,
    is_enabled INTEGER NOT NULL DEFAULT 1,
    version INTEGER NOT NULL,
    target_type TEXT NOT NULL,
    target_value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tracked_apps (
    executable_name TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    is_tracked INTEGER NOT NULL DEFAULT 1,
    discovered_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS usage_sessions (
    id TEXT PRIMARY KEY,
    target_executable TEXT NOT NULL,
    started_at TEXT NOT NULL,
    last_checkpoint_at TEXT NOT NULL,
    ended_at TEXT,
    duration_seconds INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS daily_usage (
    date TEXT NOT NULL,
    target_executable TEXT NOT NULL,
    total_duration_seconds INTEGER NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (date, target_executable)
);

CREATE TABLE IF NOT EXISTS pending_events (
    id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    target TEXT,
    reason TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    sync_status TEXT NOT NULL,
    metadata_json TEXT
);

CREATE TABLE IF NOT EXISTS sync_state (
    key TEXT PRIMARY KEY,
    val TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_usage_sessions_target ON usage_sessions(target_executable);
CREATE INDEX IF NOT EXISTS idx_usage_sessions_ended ON usage_sessions(ended_at);
CREATE INDEX IF NOT EXISTS idx_daily_usage_date ON daily_usage(date);
CREATE INDEX IF NOT EXISTS idx_pending_events_status ON pending_events(sync_status);
"#;
