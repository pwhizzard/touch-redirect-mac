#!/bin/bash
# Build script for TouchRedirect.app
# Creates a proper macOS app bundle

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_NAME="TouchRedirect"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

echo "Building TouchRedirect..."
cd "$PROJECT_DIR"

# Build release version
swift build -c release

echo "Creating app bundle..."

# Remove old bundle
rm -rf "$APP_BUNDLE"

# Create bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist
cp "$PROJECT_DIR/Sources/TouchRedirect/Info.plist" "$APP_BUNDLE/Contents/"

# Generate icons if they don't exist
ICON_DIR="$PROJECT_DIR/Sources/TouchRedirect/Resources/Assets.xcassets/AppIcon.appiconset"
if [ ! -f "$ICON_DIR/icon_1024.png" ]; then
    echo "Generating app icons..."
    swift "$SCRIPT_DIR/generate-icon.swift"
fi

# Create iconset and icns
ICONSET_DIR="$APP_BUNDLE/Contents/Resources/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# Copy icons with proper naming for iconutil
cp "$ICON_DIR/icon_16.png" "$ICONSET_DIR/icon_16x16.png" 2>/dev/null || true
cp "$ICON_DIR/icon_32.png" "$ICONSET_DIR/icon_16x16@2x.png" 2>/dev/null || true
cp "$ICON_DIR/icon_32.png" "$ICONSET_DIR/icon_32x32.png" 2>/dev/null || true
cp "$ICON_DIR/icon_64.png" "$ICONSET_DIR/icon_32x32@2x.png" 2>/dev/null || true
cp "$ICON_DIR/icon_128.png" "$ICONSET_DIR/icon_128x128.png" 2>/dev/null || true
cp "$ICON_DIR/icon_256.png" "$ICONSET_DIR/icon_128x128@2x.png" 2>/dev/null || true
cp "$ICON_DIR/icon_256.png" "$ICONSET_DIR/icon_256x256.png" 2>/dev/null || true
cp "$ICON_DIR/icon_512.png" "$ICONSET_DIR/icon_256x256@2x.png" 2>/dev/null || true
cp "$ICON_DIR/icon_512.png" "$ICONSET_DIR/icon_512x512.png" 2>/dev/null || true
cp "$ICON_DIR/icon_1024.png" "$ICONSET_DIR/icon_512x512@2x.png" 2>/dev/null || true

# Convert to icns if icons exist
if [ -f "$ICONSET_DIR/icon_512x512@2x.png" ]; then
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    echo "Created AppIcon.icns"
else
    echo "Warning: Icons not found, skipping icns generation"
    rm -rf "$ICONSET_DIR"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc code sign
echo "Code signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Build complete!"
echo "App bundle created at: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"
echo "To install: cp -r $APP_BUNDLE /Applications/"
