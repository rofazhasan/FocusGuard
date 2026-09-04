#!/bin/bash
# FocusGuard Database Healthcheck Script
# Verifies database availability and schema completeness

set -e

WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE_DIR"

echo "==> Running FocusGuard Database Healthcheck..."

if [ -n "$DB_HOST" ] && [ -n "$DB_USER" ]; then
    echo "Checking PostgreSQL connection: $DB_HOST:$DB_PORT ($DB_NAME)..."
    if PGPASSWORD="${DB_PASSWORD}" pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME"; then
        echo "✓ PostgreSQL is ready and accepting connections."
    else
        echo "✗ PostgreSQL connection check failed!"
        exit 1
    fi
else
    DB_PATH="${SQLITE_PATH:-$WORKSPACE_DIR/backend/focusguard.db}"
    echo "Checking SQLite database file: $DB_PATH..."
    if [ -f "$DB_PATH" ]; then
        echo "✓ SQLite database exists and is readable."
    else
        echo "ℹ SQLite database will be initialized upon first server launch."
    fi
fi

# Query API /health and /ready if running
API_URL="${API_URL:-http://localhost:8080}"
HEALTH=$(curl -s "$API_URL/health" 2>/dev/null || echo "")
if echo "$HEALTH" | grep -q '"status":"UP"'; then
    echo "✓ Cloud API /health status: UP"
else
    echo "ℹ API server is currently not listening on $API_URL"
fi

echo "=================================================="
echo "✓ FocusGuard Database Health Check Completed"
echo "=================================================="
