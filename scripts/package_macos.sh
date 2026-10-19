#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MACOS_DIR="$REPO_ROOT/apps/macos"
DIST_DIR="$REPO_ROOT/dist/macos"
APP_NAME="FocusGuard"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

echo "================================================================================"
echo "FOCUSGUARD PHASE 4: MACOS NATIVE CLIENT PACKAGING"
echo "================================================================================"

echo "[1/4] Cleaning previous distribution build..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "[2/4] Compiling FocusGuard release binary via SwiftPM..."
cd "$MACOS_DIR"
swift build -c release --product FocusGuardApp

RELEASE_BIN="$MACOS_DIR/.build/release/FocusGuardApp"
if [ ! -f "$RELEASE_BIN" ]; then
    echo "Error: Release binary not found at $RELEASE_BIN"
    exit 1
fi

echo "[3/4] Constructing macOS application bundle structure: $APP_NAME.app..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$RELEASE_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy App Icon and Brand Assets
if [ -d "$MACOS_DIR/FocusGuardApp/Resources" ]; then
    cp -R "$MACOS_DIR/FocusGuardApp/Resources/"* "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
fi

# Copy SwiftPM Resource Bundle if present
SWIFT_BUNDLE=$(find "$MACOS_DIR/.build" -name "FocusGuard_FocusGuardApp.bundle" 2>/dev/null | head -n 1 || true)
if [ -n "$SWIFT_BUNDLE" ] && [ -d "$SWIFT_BUNDLE" ]; then
    cp -R "$SWIFT_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

# Generate Info.plist
cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FocusGuard</string>
    <key>CFBundleIdentifier</key>
    <string>com.focusguard.macos</string>
    <key>CFBundleName</key>
    <string>FocusGuard</string>
    <key>CFBundleDisplayName</key>
    <string>FocusGuard</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc codesign bundle so Gatekeeper recognizes it
echo "[4/5] Codesigning application bundle..."
codesign --force --deep -s - "$APP_BUNDLE"

# Install directly to /Applications
echo "[5/5] Installing FocusGuard.app into /Applications..."
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"

# Generate ZIP archive for distribution
cd "$DIST_DIR"
zip -r -q "$APP_NAME-macOS-v1.0.0.zip" "$APP_NAME.app"

echo "================================================================================"
echo "SUCCESS: FocusGuard macOS app installed & packaged!"
echo "Installed to: /Applications/$APP_NAME.app"
echo "Dist Bundle:  $APP_BUNDLE"
echo "Archive:      $DIST_DIR/$APP_NAME-macOS-v1.0.0.zip"
echo "================================================================================"
