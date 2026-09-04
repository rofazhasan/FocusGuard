-- FocusGuard Phase 2 Schema Migration: Authentication, Device Identity & Secure Pairing
-- Version: 000002
-- Engine: PostgreSQL 16+

-- 1. Upgrade Users Table & User Sessions
CREATE TABLE IF NOT EXISTS user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token_hash VARCHAR(255) NOT NULL,
    user_agent VARCHAR(255),
    ip_address VARCHAR(45),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_token_hash ON user_sessions(refresh_token_hash);

-- 2. Upgrade Devices Table
ALTER TABLE devices ADD COLUMN IF NOT EXISTS client_type VARCHAR(30) DEFAULT 'EXTENSION';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS app_version VARCHAR(30) DEFAULT '1.0.0';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS protection_state VARCHAR(30) DEFAULT 'PROTECTED';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_devices_user_status ON devices(user_id, status);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices(last_seen_at);

-- 3. Device Public Identities
CREATE TABLE IF NOT EXISTS device_public_identities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    public_key TEXT NOT NULL,
    key_algorithm VARCHAR(30) NOT NULL DEFAULT 'Ed25519',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(device_id)
);

CREATE INDEX IF NOT EXISTS idx_device_public_identities_device ON device_public_identities(device_id);

-- 4. Device Credentials Metadata
CREATE TABLE IF NOT EXISTS device_credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    credential_hash VARCHAR(255) NOT NULL,
    credential_version INT NOT NULL DEFAULT 1,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_credentials_device ON device_credentials(device_id);
CREATE INDEX IF NOT EXISTS idx_device_credentials_hash ON device_credentials(credential_hash);

-- 5. Pairing Sessions
CREATE TABLE IF NOT EXISTS pairing_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash VARCHAR(255) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'CREATED',
    requested_device_metadata JSONB,
    requested_public_key TEXT,
    enrolled_device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pairing_sessions_owner ON pairing_sessions(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_pairing_sessions_code_hash ON pairing_sessions(code_hash);
CREATE INDEX IF NOT EXISTS idx_pairing_sessions_expiry ON pairing_sessions(expires_at, status);

-- 6. Policy Sync Cursors
CREATE TABLE IF NOT EXISTS sync_cursors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    last_policy_version INT NOT NULL DEFAULT 0,
    last_sync_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(device_id)
);

CREATE INDEX IF NOT EXISTS idx_sync_cursors_device ON sync_cursors(device_id);

-- 7. Audit Logs Enhancement
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS actor_type VARCHAR(30) DEFAULT 'USER';
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS actor_id VARCHAR(100);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS resource_type VARCHAR(50);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS resource_id VARCHAR(100);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS request_id VARCHAR(100);
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS metadata JSONB;

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_timestamp ON audit_logs(user_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
