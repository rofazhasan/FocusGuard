#!/usr/bin/env bash
# FocusGuard — WebExtension Production Bundler

set -e

GREEN="\033[0;32m"
BLUE="\033[0;34m"
NC="\033[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
mkdir -p "$DIST_DIR"

echo -e "${BLUE}==> Validating WebExtension Manifest and Core Tests...${NC}"
cd "$REPO_ROOT"
node apps/extension/tests/test_extension.js

echo -e "${BLUE}==> Packaging Extension Bundle for Chrome & Firefox...${NC}"
ZIP_NAME="focusguard-extension-v1.0.0.zip"
cd "$REPO_ROOT/apps/extension"
zip -r "$DIST_DIR/$ZIP_NAME" . -x "tests/*"

echo -e "\n${GREEN}✓ WebExtension successfully packaged:${NC} ${BLUE}$DIST_DIR/$ZIP_NAME${NC}"
echo -e "Ready for installation in Chrome (chrome://extensions) and Firefox (about:debugging)."
