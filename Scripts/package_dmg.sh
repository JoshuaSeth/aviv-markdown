#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Aviv"
VOLUME_NAME="Aviv Editor"
DMG_NAME="Aviv-Editor-macOS"
DMG_DIR="$ROOT/dist/dmg"
DMG_PATH="$ROOT/dist/$DMG_NAME.dmg"

"$ROOT/Scripts/package_app.sh" >/dev/null

rm -rf "$DMG_DIR" "$DMG_PATH" "$DMG_PATH.sha256"
mkdir -p "$DMG_DIR"
ditto "$ROOT/dist/$APP_NAME.app" "$DMG_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

(cd "$(dirname "$DMG_PATH")" && shasum -a 256 "$(basename "$DMG_PATH")") > "$DMG_PATH.sha256"
echo "$DMG_PATH"
