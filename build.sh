#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MicGuard"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

swiftc -O -parse-as-library \
  -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
  Sources/MicGuard/*.swift \
  -framework SwiftUI -framework AppKit -framework CoreAudio

cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

codesign --force --deep --sign - "$APP_BUNDLE"

echo "Собрано: $APP_BUNDLE"

INSTALLED="/Applications/$APP_NAME.app"
pkill -f "$INSTALLED/Contents/MacOS/$APP_NAME" 2>/dev/null || true
rm -rf "$INSTALLED"
cp -R "$APP_BUNDLE" "$INSTALLED"
echo "Установлено: $INSTALLED"
