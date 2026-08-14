#!/usr/bin/env bash
# FocusGuard — Stop All Local Services

GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

stop_pid() {
    local pid_file="$1"
    local name="$2"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
            echo -e "  [${GREEN}STOPPED${NC}] $name (PID $pid)"
        fi
        rm -f "$pid_file"
    fi
}

echo "==> Stopping FocusGuard local services..."
stop_pid "$REPO_ROOT/.pids/backend.pid" "Go Backend Server (:8080)"
stop_pid "$REPO_ROOT/.pids/web.pid" "Web Command Center (:3001)"

# Clean up any rogue processes on ports 8080 and 3001
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
lsof -ti:3001 | xargs kill -9 2>/dev/null || true

echo "✓ All FocusGuard services stopped."
