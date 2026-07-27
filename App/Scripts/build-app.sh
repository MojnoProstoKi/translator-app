#!/bin/bash
# Builds RealtimeTranslator as a signed .app bundle and zips it for transfer to another Mac.
# See specs/001-realtime-speech-translation/quickstart.md for the manual steps this replaces.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIR"

CONFIG="release"
BUNDLE_ID="com.translator.RealtimeTranslator"
APP_NAME="RealtimeTranslator"
BUILD_DIR=".build/$APP_NAME.app"
ZIP_PATH=".build/$APP_NAME.zip"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> assembling $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Contents/MacOS"
cp "$BIN_PATH" "$BUILD_DIR/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$BUILD_DIR/Contents/Info.plist"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$BUILD_DIR"

echo "==> zipping for transfer -> $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$BUILD_DIR" "$ZIP_PATH"

echo
echo "Done: $APP_DIR/$BUILD_DIR"
echo "Transfer archive: $APP_DIR/$ZIP_PATH"
echo
echo "Bundle identifier: $BUNDLE_ID"
echo "On the target Mac (Apple Silicon, macOS 26+):"
echo "  1. Unzip and move RealtimeTranslator.app to /Applications (or anywhere)."
echo "  2. If macOS blocks the first launch (\"cannot be opened, unidentified developer\" —"
echo "     happens if the archive was sent via AirDrop/Mail/browser, which adds a quarantine flag):"
echo "     right-click the app -> Open -> Open, or clear it manually:"
echo "       xattr -dr com.apple.quarantine /Applications/RealtimeTranslator.app"
echo "  3. Grant System Settings -> Privacy & Security -> System Audio Recording Only -> '+' ->"
echo "     RealtimeTranslator.app (only needed for the system-audio source; no system prompt exists"
echo "     for this permission, see quickstart.md)."
echo "  4. Launch the app; microphone/speech-recognition prompts appear automatically on first use."
