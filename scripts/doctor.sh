#!/usr/bin/env bash
# FocusGuard System Doctor — Environment Diagnostics

set -e

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
NC="\033[0m"

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}        FOCUSGUARD SYSTEM ENVIRONMENT DOCTOR         ${NC}"
echo -e "${BLUE}=====================================================${NC}"

CHECK_FAIL=0

check_cmd() {
    local name="$1"
    local cmd="$2"
    local version_flag="$3"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        local ver
        ver=$($cmd $version_flag 2>&1 | head -n 1)
        echo -e "  [${GREEN}✓ PASS${NC}] $name: $ver"
    else
        echo -e "  [${RED}✗ FAIL${NC}] $name: '$cmd' is not installed or not in PATH."
        CHECK_FAIL=1
    fi
}

echo -e "\n1. Core Languages & Runtime Engines:"
check_cmd "Go Compiler" "go" "version"
check_cmd "Node.js Engine" "node" "--version"
check_cmd "NPM Package Manager" "npm" "--version"

echo -e "\n2. Native Platform Compilers:"
if [[ "$OSTYPE" == "darwin"* ]]; then
    check_cmd "Apple Swift Compiler" "swift" "--version"
    check_cmd "Xcode Command Line Tools" "xcode-select" "-p"
else
    echo -e "  [${YELLOW}INFO${NC}] Non-macOS environment detected; macOS Screen Time tests will use mock runner."
fi

if command -v adb >/dev/null 2>&1; then
    check_cmd "Android Debug Bridge" "adb" "--version"
else
    echo -e "  [${YELLOW}INFO${NC}] Android SDK ADB not detected (Optional for backend/web dev)."
fi

echo -e "\n3. Container & Database Infrastructure:"
if command -v docker >/dev/null 2>&1; then
    check_cmd "Docker Engine" "docker" "--version"
else
    echo -e "  [${YELLOW}INFO${NC}] Docker not found (Using embedded SQLite for zero-dependency local run)."
fi

echo -e "\n-----------------------------------------------------"
if [ $CHECK_FAIL -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL CORE PREREQUISITES VERIFIED! FocusGuard is ready.${NC}"
    echo -e "Run '${BLUE}make start${NC}' or '${BLUE}./scripts/start-all.sh${NC}' to launch."
else
    echo -e "${RED}⚠️ Some core dependencies are missing. Please review above.${NC}"
fi
echo -e "-----------------------------------------------------\n"
