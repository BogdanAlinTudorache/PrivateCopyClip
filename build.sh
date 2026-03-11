#!/bin/bash

# CopyClip Build Script
# Compiles Swift source and creates macOS app bundle

set -e

APP_NAME="PrivateCopyClip"
BUNDLE_ID="com.privatecopy.clipboard"
VERSION="1.0"
BUILD_DIR="$(pwd)/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Building $APP_NAME..."

# Create build directory
mkdir -p "$BUILD_DIR"
rm -rf "$APP_BUNDLE"

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Compile Swift source
echo "📦 Compiling Swift source..."
swiftc main.swift \
    -parse-as-library \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -suppress-warnings

# Make executable
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PrivateCopyClip</string>
    <key>CFBundleIdentifier</key>
    <string>com.privatecopy.clipboard</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PrivateCopyClip</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSMainStoryboardFile</key>
    <string></string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSRequiresIPhoneOS</key>
    <false/>
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
    </array>
    <key>UIMainStoryboardFile</key>
    <string>Main</string>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>armv7</string>
    </array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
</dict>
</plist>
EOF

echo "✅ Build successful!"
echo "📱 App bundle: $APP_BUNDLE"
echo ""
echo "📋 To run:"
echo "   open \"$APP_BUNDLE\""
echo ""
echo "📱 To install to Applications folder:"
echo "   cp -r \"$APP_BUNDLE\" /Applications/"
