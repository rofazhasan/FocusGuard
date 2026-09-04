#!/bin/bash
# FocusGuard Database Seed Script
# Seeds default primary user and initial demo policies for local testing

set -e

WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE_DIR"

echo "==> Seeding FocusGuard Database..."

API_URL="${API_URL:-http://localhost:8080}"

# Check API health first
if curl -s "$API_URL/health" | grep -q '"status":"UP"'; then
    echo "API server is online. Performing authenticated bootstrap seed..."
    
    # Register/Login Demo User
    LOGIN_RESP=$(curl -s -X POST "$API_URL/api/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"email":"demo@focusguard.local","password":"focusguard123"}')
    
    TOKEN=$(echo "$LOGIN_RESP" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
    if [ -z "$TOKEN" ]; then
        echo "Registering initial user..."
        REG_RESP=$(curl -s -X POST "$API_URL/api/v1/auth/register" \
            -H "Content-Type: application/json" \
            -d '{"email":"demo@focusguard.local","password":"focusguard123"}')
        TOKEN=$(echo "$REG_RESP" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
    fi

    if [ -n "$TOKEN" ]; then
        echo "✓ Seeded primary user: demo@focusguard.local"
        
        # Create default YouTube attention budget policy
        curl -s -X POST "$API_URL/api/v1/policies" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $TOKEN" \
            -d '{
                "name": "Daily YouTube Focus Budget",
                "limitSeconds": 1800,
                "period": "DAILY",
                "enforcementMode": "BLOCK",
                "targets": [{"targetType": "WEBSITE", "targetValue": "youtube.com"}]
            }' > /dev/null || true
        echo "✓ Seeded default YouTube attention budget policy (30m daily)"
    fi
else
    echo "Note: API server ($API_URL) is not currently running. Schema will auto-seed upon server launch."
fi

echo "✓ Seeding complete."
