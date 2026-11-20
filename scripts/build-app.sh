#!/bin/bash
set -e

# Base directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

APP_NAME="DadSearch"
BUILD_DIR="$DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

echo "🔨 Building $APP_NAME release binary..."
swift build -c release

RELEASE_BIN="$DIR/.build/release/$APP_NAME"

echo "📦 Creating macOS App Bundle..."
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary, Info.plist, and Icon
cp "$RELEASE_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$DIR/Resources/AppIcon.png" "$APP_BUNDLE/Contents/Resources/AppIcon.png"

# Set executable permissions
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "🔏 Ad-hoc code signing $APP_NAME.app..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "💿 Creating $APP_NAME.dmg installer..."
DMG_STAGING="$BUILD_DIR/dmg_staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Add link to /Applications
ln -s /Applications "$DMG_STAGING/Applications"

# Add custom volume icon to DMG if available
cp "$DIR/Resources/AppIcon.icns" "$DMG_STAGING/.VolumeIcon.icns" 2>/dev/null || true

# Build DMG using hdiutil
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"

rm -rf "$DMG_STAGING"

# Also create zip archive of the .app
ditto -c -k --keepParent "$APP_BUNDLE" "$BUILD_DIR/$APP_NAME.zip"

echo "✅ Successfully created:"
echo "   App Bundle: $APP_BUNDLE"
echo "   DMG:        $DMG_PATH"
echo "   ZIP:        $BUILD_DIR/$APP_NAME.zip"
