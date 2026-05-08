#!/bin/bash
set -e

VERSION="${PHONOS_VERSION:-$(git describe --tags --always 2>/dev/null || echo "0.0.0")}"
VERSION="${VERSION#v}"
BUILD="${PHONOS_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo "0")}"

echo "=== Building Phonos ${VERSION} (build ${BUILD}) ==="

# Build the binary
swift build -c release 2>&1

# Create app bundle (clean slate)
APP_DIR=".build/Phonos.app"
if [ -d "$APP_DIR" ]; then
    chmod -R u+w "$APP_DIR" 2>/dev/null || true
fi
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# Copy binary
cp .build/release/Phonos "$APP_DIR/Contents/MacOS/Phonos"

# Copy SwiftPM resource bundles into the conventional app resources location.
find .build -maxdepth 5 -path "*/release/*.bundle" -type d ! -path "*/index-build/*" -print0 |
    while IFS= read -r -d '' bundle; do
        destination="$APP_DIR/Contents/Resources/$(basename "$bundle")"
        rm -rf "$destination"
        ditto "$bundle" "$destination"
    done

# Copy brand assets.
if [ -f "Assets/Brand/PhonosLogo.png" ]; then
    cp "Assets/Brand/PhonosLogo.png" "$APP_DIR/Contents/Resources/PhonosLogo.png"
fi

# Copy custom menu-bar template icons.
if [ -d "Assets/MenuBar" ]; then
    find "Assets/MenuBar" -maxdepth 1 -type f -name "*.png" -exec cp {} "$APP_DIR/Contents/Resources/" \;
fi

# Copy app icon when the generated macOS icon asset is available.
if [ -f "Assets/AppIcon.icns" ]; then
    cp "Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Fix permissions
chmod -R u+rwX,go+rX "$APP_DIR"

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
    <!--
      App Transport Security (ATS)
      NSAllowsArbitraryLoads is required because users may configure arbitrary
      server URLs, including Tailscale IPs (100.x.x.x) and LAN addresses that
      are not covered by NSAllowsLocalNetworking (which only exempts RFC 1918
      private ranges and .local domains). NSExceptionDomains cannot be used
      because the domain/IP is user-configured and not known at build time.
      All connections are still protected by the optional bearer-token auth
      layer configured in the Phonos server.
    -->
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
hdiutil create -volname "Phonos" -srcfolder "$DMG_DIR" -ov -format UDZO -fs APFS "$DMG_NAME" 2>&1
rm -rf "$DMG_DIR"

echo ""
echo "=== Build complete ==="
echo "App at:  $APP_DIR"
echo "DMG at:  $DMG_NAME"
echo ""
echo "First launch will prompt for permissions."
echo "If not, grant manually: open Phonos.dmg"
echo "Then drag Phonos.app into the Applications folder."
