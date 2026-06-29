#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Aviv"
BUNDLE_ID="local.aviv.markdown"
SOURCE_APP="$ROOT/dist/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cd "$ROOT"
"$ROOT/Scripts/package_app.sh" >/dev/null

install_app() {
    local install_parent="$1"
    local target_app="$install_parent/$APP_NAME.app"

    mkdir -p "$install_parent"
    rm -rf "$target_app"
    ditto "$SOURCE_APP" "$target_app"
    codesign --verify --deep --strict "$target_app"
    "$LSREGISTER" -f "$target_app"
    echo "$target_app"
}

INSTALL_PARENT="${AVIV_INSTALL_PARENT:-/Applications}"
if ! TARGET_APP="$(install_app "$INSTALL_PARENT" 2>/tmp/aviv-install-error.log)"; then
    INSTALL_PARENT="$HOME/Applications"
    TARGET_APP="$(install_app "$INSTALL_PARENT")"
fi

if ! swift "$ROOT/Scripts/launch_services_markdown_default.swift" set --bundle-id "$BUNDLE_ID"; then
    swift "$ROOT/Scripts/launch_services_markdown_default.swift" force-preferences --bundle-id "$BUNDLE_ID"
    killall cfprefsd 2>/dev/null || true
    "$LSREGISTER" -f "$TARGET_APP"
fi
swift "$ROOT/Scripts/launch_services_markdown_default.swift" verify --bundle-id "$BUNDLE_ID"

echo "installed: $TARGET_APP"
echo "default Markdown handler: $BUNDLE_ID"
