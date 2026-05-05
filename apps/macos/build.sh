#!/bin/bash
set -e

VERSION="${PHONOS_VERSION:-$(git describe --tags --always 2>/dev/null || echo "0.0.0")}"
BUILD="${PHONOS_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo "0")}"

echo "=== Building Phonos ${VERSION} (build ${BUILD}) ==="

# Build the binary
swift build -c release 2>&1

# Create app bundle (clean slate)
APP_DIR=".build/Phonos.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# Copy binary
cp .build/release/Phonos "$APP_DIR/Contents/MacOS/Phonos"

# Copy SwiftPM resource bundles into the conventional app resources location.
find .build -maxdepth 5 -path "*/release/*.bundle" -type d -exec cp -R {} "$APP_DIR/Contents/Resources/" \;

# Fix permissions
chmod -R a+rX "$APP_DIR"

# Write Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Phonos</string>
    <key>CFBundleIdentifier</key>
    <string>dev.phonos.app</string>
    <key>CFBundleName</key>
    <string>Phonos</string>
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
    <key>NSMicrophoneUsageDescription</key>
    <string>Phonos needs microphone access to capture audio for transcription.</string>
</dict>
</plist>
PLIST

# Determine signing identity
SIGN_IDENTITY="${PHONOS_CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | awk '/Phonos Local Development|Apple Development|Developer ID Application|Mac Developer/ { print $2; exit }')
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing with: $SIGN_IDENTITY"
else
    SIGN_IDENTITY="-"
    echo "Warning: no stable code-signing identity found; using ad-hoc signing."
    echo "Accessibility permission may need to be re-granted after each rebuild."
fi

# Sign the app (no files outside Contents/, so codesign is happy)
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"

# Create DMG
echo ""
echo "=== Creating DMG ==="
DMG_DIR=$(mktemp -d)
cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"
DMG_NAME="Phonos.dmg"
hdiutil create -volname "Phonos" -srcfolder "$DMG_DIR" -ov -format UDZO -fs HFS+ "$DMG_NAME" 2>&1
rm -rf "$DMG_DIR"

echo ""
echo "=== Build complete ==="
echo "App at:  $APP_DIR"
echo "DMG at:  $DMG_NAME"
echo ""
echo "First launch will prompt for permissions."
echo "If not, grant manually: open Phonos.dmg"
echo "Then drag Phonos.app into the Applications folder."
