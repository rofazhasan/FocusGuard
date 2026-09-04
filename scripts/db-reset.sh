#!/bin/bash
# FocusGuard Database Reset Script
# Supports both embedded SQLite and external PostgreSQL

set -e

WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE_DIR"

echo "==> Resetting FocusGuard Database..."

if [ -n "$DB_HOST" ] && [ -n "$DB_USER" ]; then
    echo "Resetting PostgreSQL database: $DB_NAME on $DB_HOST:$DB_PORT..."
    PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        DROP TABLE IF EXISTS sync_cursors, pairing_sessions, device_credentials, device_public_identities,
            user_sessions, enrollment_tokens, audit_logs, blocked_events, usage_aggregates,
            policy_assignments, policy_targets, policies, devices, users, focus_sessions, remote_commands CASCADE;
    "
    echo "✓ PostgreSQL tables dropped."
else
    DB_PATH="${SQLITE_PATH:-$WORKSPACE_DIR/backend/focusguard.db}"
    if [ -f "$DB_PATH" ]; then
        rm -f "$DB_PATH" "$DB_PATH-shm" "$DB_PATH-wal"
        echo "✓ Removed SQLite database file: $DB_PATH"
    fi
fi

echo "✓ FocusGuard database reset complete."
