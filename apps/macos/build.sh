#!/bin/bash
set -e

echo "=== Building Phonos ==="

# Build the binary
swift build -c release 2>&1

# Create app bundle
APP_DIR=".build/Phonos.app"
mkdir -p "$APP_DIR/Contents/MacOS"

# Copy binary
cp .build/release/Phonos "$APP_DIR/Contents/MacOS/Phonos"

# Write Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
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
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Phonos needs Accessibility access for global hotkey detection and paste automation.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Phonos needs microphone access to capture audio for transcription.</string>
</dict>
</plist>
PLIST

echo ""
echo "=== Build complete ==="
echo "App at: $APP_DIR"
echo ""
echo "First launch will prompt for permissions."
echo "If not, grant manually: open $APP_DIR from Finder"
echo "or drag it into System Settings → Privacy & Security → Accessibility"
