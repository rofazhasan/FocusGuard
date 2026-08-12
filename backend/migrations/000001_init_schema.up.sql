-- FocusGuard Database Initial Migration Schema
-- Version: 000001
-- Engine: PostgreSQL 16+

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Users Table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Devices Table
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_name VARCHAR(100) NOT NULL,
    platform VARCHAR(20) NOT NULL, -- 'MACOS', 'ANDROID'
    os_version VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ONLINE',
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);

-- 3. Policies Table
CREATE TABLE IF NOT EXISTS policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    limit_seconds INT NOT NULL DEFAULT 0,
    period VARCHAR(20) NOT NULL DEFAULT 'DAILY', -- 'DAILY', 'WEEKLY'
    schedule_cron VARCHAR(100),
    timezone VARCHAR(50) NOT NULL DEFAULT 'UTC',
    enforcement_mode VARCHAR(30) NOT NULL DEFAULT 'BLOCK', -- 'BLOCK', 'FOCUS_ONLY', 'SCHEDULED_BLOCK'
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_policies_user_id ON policies(user_id);

-- 4. Policy Targets Table
CREATE TABLE IF NOT EXISTS policy_targets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_id UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
    target_type VARCHAR(20) NOT NULL, -- 'APP', 'WEBSITE', 'CATEGORY'
    target_value VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_policy_targets_policy_id ON policy_targets(policy_id);

-- 5. Policy Devices Mapping Table
CREATE TABLE IF NOT EXISTS policy_devices (
    policy_id UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    PRIMARY KEY (policy_id, device_id)
);

-- 6. Usage Aggregates Table
CREATE TABLE IF NOT EXISTS usage_aggregates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    target_value VARCHAR(255) NOT NULL,
    date DATE NOT NULL,
    total_duration_seconds INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, device_id, target_value, date)
);

CREATE INDEX IF NOT EXISTS idx_usage_aggregates_user_date ON usage_aggregates(user_id, date);

-- 7. Blocked Events Table
CREATE TABLE IF NOT EXISTS blocked_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    policy_id UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
    target_value VARCHAR(255) NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_blocked_events_user_id ON blocked_events(user_id);
