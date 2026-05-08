#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIGURATION="${PHONOS_DEV_CONFIGURATION:-debug}"
APP_DIR="${PHONOS_DEV_APP_DIR:-$PWD/.build/dev/Phonos.app}"
BUNDLE_IDENTIFIER="${PHONOS_BUNDLE_IDENTIFIER:-dev.phonos.app}"
VERSION="${PHONOS_VERSION:-dev}"
VERSION="${VERSION#v}"
BUILD="${PHONOS_BUILD:-$(date +%Y%m%d%H%M%S)}"

echo "=== Building Phonos for development (${CONFIGURATION}) ==="
swift build -c "$CONFIGURATION"

BUILD_DIR=".build/${CONFIGURATION}"
BINARY_PATH="${BUILD_DIR}/Phonos"

if [ ! -x "$BINARY_PATH" ]; then
    echo "error: expected built binary at ${BINARY_PATH}" >&2
    exit 1
fi

echo ""
echo "=== Creating development app bundle ==="
if [ -d "$APP_DIR" ]; then
    chmod -R u+w "$APP_DIR" 2>/dev/null || true
fi
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/Phonos"

# Copy SwiftPM resource bundles into the conventional app resources location.
find .build -maxdepth 5 -path "*/${CONFIGURATION}/*.bundle" -type d ! -path "*/index-build/*" -print0 |
    while IFS= read -r -d '' bundle; do
        destination="$APP_DIR/Contents/Resources/$(basename "$bundle")"
        rm -rf "$destination"
        ditto "$bundle" "$destination"
    done

if [ -f "Assets/AppIcon.icns" ]; then
    cp "Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

if [ -f "Assets/Brand/PhonosLogo.png" ]; then
    cp "Assets/Brand/PhonosLogo.png" "$APP_DIR/Contents/Resources/PhonosLogo.png"
fi

if [ -d "Assets/MenuBar" ]; then
    find "Assets/MenuBar" -maxdepth 1 -type f -name "*.png" -exec cp {} "$APP_DIR/Contents/Resources/" \;
fi

chmod -R u+rwX,go+rX "$APP_DIR"

cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Phonos</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_IDENTIFIER}</string>
    <key>CFBundleName</key>
    <string>Phonos</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Phonos needs Accessibility access for paste automation.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSMicrophoneUsageDescription</key>
    <string>Phonos needs microphone access to capture audio for transcription.</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${PHONOS_CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | awk '/Phonos Local Development|Apple Development|Developer ID Application|Mac Developer/ { print $2; exit }')
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing with: $SIGN_IDENTITY"
else
    SIGN_IDENTITY="-"
    echo "Warning: no stable code-signing identity found; using ad-hoc signing."
    echo "Microphone and Accessibility permissions may need to be re-granted after rebuilds."
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"

echo ""
echo "=== Cleaning up mounted Phonos DMGs ==="
if [ "${PHONOS_DEV_EJECT_DMG:-1}" = "1" ]; then
    shopt -s nullglob
    for volume in /Volumes/Phonos*; do
        hdiutil detach "$volume" >/dev/null 2>&1 || true
    done
    shopt -u nullglob
else
    echo "Skipping DMG eject because PHONOS_DEV_EJECT_DMG=0."
fi

echo ""
if [ "${PHONOS_DEV_LAUNCH:-1}" = "1" ]; then
    echo "=== Restarting Phonos ==="
    if pgrep -x Phonos >/dev/null; then
        osascript -e "tell application id \"${BUNDLE_IDENTIFIER}\" to quit" >/dev/null 2>&1 || true
        for _ in {1..20}; do
            pgrep -x Phonos >/dev/null || break
            sleep 0.1
        done
        if pgrep -x Phonos >/dev/null; then
            pkill -x Phonos || true
        fi
    fi
    open "$APP_DIR"
else
    echo "Skipping app restart because PHONOS_DEV_LAUNCH=0."
fi

echo ""
echo "=== Development run complete ==="
echo "App at: $APP_DIR"
echo ""
echo "macOS does not allow scripts to grant Microphone or Accessibility permissions."
echo "Use a stable signing identity so the first manual grant sticks across rebuilds."
