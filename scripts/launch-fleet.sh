#!/usr/bin/env bash
# FocusGuard — Fleet Launch & Orchestration Script
# Launches the full production fleet: Backend, Web Dashboard, macOS App, and Chrome Extension

set -e

GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
NC="\033[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BLUE}=======================================================================${NC}"
echo -e "${BLUE}  🚀 LAUNCHING FOCUSGUARD FULL ECOSYSTEM                               ${NC}"
echo -e "${BLUE}=======================================================================${NC}"

# 1. Start or verify backend and web dashboard
"$REPO_ROOT/scripts/start-all.sh"

# 2. Check and launch macOS Application
echo -e "\n${BLUE}==> Launching FocusGuard Native macOS Application...${NC}"
if [ -d "/Applications/FocusGuard.app" ]; then
    open "/Applications/FocusGuard.app"
    echo -e "${GREEN}✓ FocusGuard.app launched from /Applications!${NC}"
else
    echo -e "${YELLOW}Notice: /Applications/FocusGuard.app not found. Running package_macos.sh first...${NC}"
    "$REPO_ROOT/scripts/package_macos.sh"
    open "/Applications/FocusGuard.app"
fi

# 3. Launch Google Chrome with Extension
echo -e "\n${BLUE}==> Launching Google Chrome with FocusGuard Extension loaded...${NC}"
EXTENSION_PATH="$REPO_ROOT/apps/extension"

if [ -d "/Applications/Google Chrome.app" ]; then
    open -a "Google Chrome" "http://localhost:3001" --args --load-extension="$EXTENSION_PATH"
    echo -e "${GREEN}✓ Google Chrome opened with FocusGuard Extension!${NC}"
else
    echo -e "${YELLOW}Notice: Google Chrome not found in /Applications. You can load $EXTENSION_PATH into any Chromium browser.${NC}"
fi

echo -e "\n${GREEN}=======================================================================${NC}"
echo -e "${GREEN}  🌟 FLEET SUCCESSFULLY ORCHESTRATED!                                 ${NC}"
echo -e "${GREEN}=======================================================================${NC}"
echo -e "  1. 🌐 Web Command Center: http://localhost:3001"
echo -e "  2. 💻 macOS App: Running in Menu Bar & Dock (/Applications/FocusGuard.app)"
echo -e "  3. 🧩 Extension: Loaded in Google Chrome (apps/extension)"
echo -e "     -> Open chrome://extensions to toggle 'Allow in incognito'"
echo -e "=======================================================================\n"
