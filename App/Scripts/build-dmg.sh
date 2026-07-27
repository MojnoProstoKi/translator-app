#!/bin/bash
# Builds RealtimeTranslator.app (via build-app.sh) and packages it into a drag-and-drop .dmg
# installer: double-click the .dmg, drag the app onto the Applications shortcut.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIR"

APP_NAME="RealtimeTranslator"
APP_BUNDLE=".build/$APP_NAME.app"
STAGING_DIR=".build/dmg-staging"
DMG_PATH=".build/$APP_NAME.dmg"

echo "==> building $APP_NAME.app"
"$APP_DIR/Scripts/build-app.sh"

echo "==> staging DMG contents"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> creating $DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -fs HFS+ -format UDZO -ov "$DMG_PATH"
rm -rf "$STAGING_DIR"

echo
echo "Done: $APP_DIR/$DMG_PATH"
echo
echo "On the target Mac (Apple Silicon, macOS 26+):"
echo "  1. Open the .dmg, drag RealtimeTranslator.app onto the Applications shortcut."
echo "  2. If macOS blocks the first launch (\"unidentified developer\" — happens if the .dmg was"
echo "     sent via AirDrop/Mail/browser, which adds a quarantine flag): right-click the app in"
echo "     /Applications -> Open -> Open, or clear it manually:"
echo "       xattr -dr com.apple.quarantine /Applications/RealtimeTranslator.app"
echo "  3. Grant System Settings -> Privacy & Security -> System Audio Recording Only -> '+' ->"
echo "     RealtimeTranslator.app (only needed for the system-audio source; no system prompt exists"
echo "     for this permission, see quickstart.md)."
echo "  4. Launch the app; microphone/speech-recognition prompts appear automatically on first use."
