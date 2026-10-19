#!/usr/bin/env bash
# FocusGuard — Full Stack Local Runner (Backend :8080 & Web Dashboard :3001)

set -e

GREEN="\033[0;32m"
BLUE="\033[0;34m"
NC="\033[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$REPO_ROOT/.pids"

echo -e "${BLUE}==> Starting FocusGuard Cloud API Backend (:8080)...${NC}"
cd "$REPO_ROOT/backend"
if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi
if [ ! -f "bin/server" ]; then
  go build -o bin/server cmd/server/main.go
fi
nohup ./bin/server > "$REPO_ROOT/.pids/backend.log" 2>&1 </dev/null &
BACKEND_PID=$!
disown $BACKEND_PID 2>/dev/null || true
echo $BACKEND_PID > "$REPO_ROOT/.pids/backend.pid"

# Wait for backend to become ready
sleep 1.5

echo -e "${BLUE}==> Starting FocusGuard Fleet Command Center (:3001)...${NC}"
cd "$REPO_ROOT/apps/web"
PORT=3001 nohup node "$REPO_ROOT/apps/web/server.js" > "$REPO_ROOT/.pids/web.log" 2>&1 </dev/null &
WEB_PID=$!
echo $WEB_PID > "$REPO_ROOT/.pids/web.pid"

sleep 1

echo -e "\n${GREEN}=======================================================================${NC}"
echo -e "${GREEN}  🎉 FOCUSGUARD SERVICES RUNNING LOCALLY!                              ${NC}"
echo -e "${GREEN}=======================================================================${NC}"
echo -e "  🌐 Fleet Command Center: ${BLUE}http://localhost:3001${NC}"
echo -e "  ⚙️ REST API Endpoint:   ${BLUE}http://localhost:8080/api/v1${NC}"
echo -e "  🔌 WebSocket Gateway:    ${BLUE}ws://localhost:8080/ws${NC}"
echo -e "  📄 Health Check:         ${BLUE}http://localhost:8080/health${NC}"
echo -e "======================================================================="
echo -e "  Process Logs:"
echo -e "    Backend: .pids/backend.log (PID $BACKEND_PID)"
echo -e "    Web UI:  .pids/web.log (PID $WEB_PID)"
echo -e "\n  To stop services, run: ${BLUE}make stop${NC} or ${BLUE}./scripts/stop-all.sh${NC}\n"
