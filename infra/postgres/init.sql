-- FocusGuard Initial Schema Migration (PostgreSQL)

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users Table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Devices Table
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_name VARCHAR(100) NOT NULL,
    platform VARCHAR(20) NOT NULL CHECK (platform IN ('MACOS', 'ANDROID')),
    os_version VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ONLINE' CHECK (status IN ('ONLINE', 'OFFLINE', 'UNREGISTERED')),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Policies Table
CREATE TABLE IF NOT EXISTS policies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    limit_seconds INT NOT NULL DEFAULT 0,
    period VARCHAR(20) NOT NULL DEFAULT 'DAILY' CHECK (period IN ('DAILY', 'WEEKLY')),
    schedule_cron VARCHAR(100),
    timezone VARCHAR(50) NOT NULL DEFAULT 'UTC',
    enforcement_mode VARCHAR(30) NOT NULL DEFAULT 'BLOCK' CHECK (enforcement_mode IN ('BLOCK', 'FOCUS_ONLY', 'SCHEDULED_BLOCK')),
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Policy Targets Table
CREATE TABLE IF NOT EXISTS policy_targets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    policy_id UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
    target_type VARCHAR(20) NOT NULL CHECK (target_type IN ('APP', 'WEBSITE', 'CATEGORY')),
    target_value VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Usage Aggregates Table
CREATE TABLE IF NOT EXISTS usage_aggregates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    target_value VARCHAR(255) NOT NULL,
    date DATE NOT NULL,
    total_duration_seconds INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_user_device_target_date UNIQUE (user_id, device_id, target_value, date)
);

-- Blocked Events Audit Table
CREATE TABLE IF NOT EXISTS blocked_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    policy_id UUID REFERENCES policies(id) ON DELETE SET NULL,
    target_value VARCHAR(255) NOT NULL,
    blocked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reason VARCHAR(100) NOT NULL
);

-- Indexes for Query Performance
CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);
CREATE INDEX IF NOT EXISTS idx_policies_user_id ON policies(user_id);
CREATE INDEX IF NOT EXISTS idx_policy_targets_policy_id ON policy_targets(policy_id);
CREATE INDEX IF NOT EXISTS idx_usage_aggregates_user_date ON usage_aggregates(user_id, date);
