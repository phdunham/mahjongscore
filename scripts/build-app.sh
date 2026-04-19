#!/usr/bin/env bash
# Build a minimal macOS .app bundle wrapping the SwiftPM executable.
#
# Output: ./build/MahjongScore.app (drag to /Applications, or double-click in place)
#
# The bundle contains:
#   Contents/MacOS/MahjongScore            — the release binary
#   Contents/MacOS/MahjongCore_MahjongCore.bundle — bundled Rules.json etc.
#   Contents/Info.plist                    — minimum metadata for Launch Services
#
# The SwiftPM resource-bundle lookup walks executable-relative paths, so placing
# the .bundle alongside the binary in MacOS/ is the safest location.
set -euo pipefail

APP_NAME="MahjongScore"
BUNDLE_ID="com.mahjongscore.app"
VERSION="0.1"
MIN_MACOS="14.0"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

echo "==> Building release"
swift build -c release

EXEC_PATH=".build/release/MahjongScoreApp"
if [[ ! -f "$EXEC_PATH" ]]; then
    echo "ERROR: release binary not found at $EXEC_PATH" >&2
    exit 1
fi

APP_DIR="build/${APP_NAME}.app"
echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "$EXEC_PATH" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Copy the SwiftPM-generated resources bundle alongside the executable so
# Bundle.module's executable-relative lookup finds Rules.json.
for candidate in \
    ".build/release/MahjongCore_MahjongCore.bundle" \
    ".build/release/MahjongScore_MahjongCore.bundle" ; do
    if [[ -d "$candidate" ]]; then
        echo "==> Copying resource bundle $(basename "$candidate")"
        cp -R "$candidate" "${APP_DIR}/Contents/MacOS/"
    fi
done

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper is slightly less angry on first launch. A personal
# Developer ID would be preferable but ad-hoc is enough for local use.
if command -v codesign >/dev/null 2>&1; then
    echo "==> Ad-hoc signing"
    codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
fi

echo ""
echo "Built: $APP_DIR"
echo ""
echo "Next steps:"
echo "  1. Launch once from the terminal so Gatekeeper registers the path:"
echo "       open '$APP_DIR'"
echo "  2. Or drag $APP_DIR into /Applications"
echo "  3. First run: click 'API Key…' in the app and paste your key."
