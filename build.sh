#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/鼠标快点.app"
MODULE_CACHE="$DIST_DIR/module-cache"
EXECUTABLE="$APP_DIR/Contents/MacOS/MacAutoClicker"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Info.plist")

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
xcrun swiftc \
    -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
    -framework AppKit \
    -framework ApplicationServices \
    "$PROJECT_DIR/AutoClicker.swift" \
    -o "$EXECUTABLE"

cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/AppIcon-source.png" "$APP_DIR/Contents/Resources/AppIcon.png"
chmod +x "$EXECUTABLE"

# Ad-hoc signing is suitable for local source builds. GitHub Release assets are
# signed separately with the project's stable local certificate.
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

ditto -c -k --sequesterRsrc --keepParent \
    "$APP_DIR" \
    "$DIST_DIR/鼠标快点-v$VERSION-macOS.zip"

echo "Built: $DIST_DIR/鼠标快点-v$VERSION-macOS.zip"

