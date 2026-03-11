#!/bin/bash

# PrivateCopyClip Build Script
set -e

APP_NAME="PrivateCopyClip"
BUILD_DIR="$(pwd)/build"
CONTENTS_DIR="$BUILD_DIR/$APP_NAME.app/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$(pwd)/iconset"

echo "🔨 Building $APP_NAME..."

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Generate icon if iconset folder is missing
if [ ! -d "$ICONSET_DIR" ]; then
    echo "🎨 Generating app icon..."
    ./generate_icon.sh
fi

# Compile iconset → .icns
echo "🎨 Compiling app icon..."
TMPSET=$(mktemp -d)
cp -r "$ICONSET_DIR" "$TMPSET/AppIcon.iconset"
iconutil -c icns -o "$RESOURCES_DIR/AppIcon.icns" "$TMPSET/AppIcon.iconset"
rm -rf "$TMPSET"

# Compile Swift source
echo "📦 Compiling Swift source..."
swiftc main.swift \
    -parse-as-library \
    -o "$MACOS_DIR/$APP_NAME" \
    -suppress-warnings

chmod +x "$MACOS_DIR/$APP_NAME"

# Write Info.plist — LSUIElement suppresses dock icon
cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>PrivateCopyClip</string>
    <key>CFBundleIdentifier</key>
    <string>com.bogdantudorache.PrivateCopyClip</string>
    <key>CFBundleName</key>
    <string>PrivateCopyClip</string>
    <key>CFBundleDisplayName</key>
    <string>PrivateCopyClip</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo ""
echo "✅ Build complete!"
echo "   $BUILD_DIR/$APP_NAME.app"
echo ""

# Quit running instance before replacing
if pgrep -x "$APP_NAME" > /dev/null; then
    echo "⏹  Quitting running $APP_NAME..."
    pkill -x "$APP_NAME"
    sleep 0.5
fi

# Install to Applications
echo "📦 Installing to /Applications..."
rm -rf "/Applications/$APP_NAME.app"
cp -r "$BUILD_DIR/$APP_NAME.app" "/Applications/"
echo "✅ Installed: /Applications/$APP_NAME.app"
echo ""

# Relaunch
echo "▶  Launching $APP_NAME..."
open "/Applications/$APP_NAME.app"
