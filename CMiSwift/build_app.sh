#!/bin/sh
# Builds CMi.app into build/: the Swift package plus VLCKit.
# Usage: ./build_app.sh [debug|release] [--universal]
set -e
cd "$(dirname "$0")"

CONFIG="${1:-release}"
ARCHS=""
if [ "$2" = "--universal" ]; then
    ARCHS="--arch arm64 --arch x86_64"
fi

swift build -c "$CONFIG" $ARCHS
BIN="$(swift build -c "$CONFIG" $ARCHS --show-bin-path)"

APP=build/CMi.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN/CMi" "$APP/Contents/MacOS/CMi"
cp Info.plist "$APP/Contents/Info.plist"
cp icon.icns "$APP/Contents/Resources/icon.icns"
ditto ../Frameworks/VLCKit.framework "$APP/Contents/Frameworks/VLCKit.framework"
codesign --force --sign - "$APP/Contents/Frameworks/VLCKit.framework"
codesign --force --sign - "$APP"
echo "Built $APP"
