#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="Aviv"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICONSET="$ROOT/dist/Aviv.iconset"
ICON="$RESOURCES/Aviv.icns"
ZIP="$ROOT/dist/Aviv-macOS.zip"

cd "$ROOT"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/.build/$CONFIGURATION/Aviv" "$MACOS/Aviv"
swift "$ROOT/Scripts/make_icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ICON"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Aviv</string>
    <key>CFBundleIdentifier</key>
    <string>local.aviv.markdown</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Aviv</string>
    <key>CFBundleDisplayName</key>
    <string>Aviv</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>Aviv</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeIconFile</key>
            <string>Aviv</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>md</string>
                <string>markdown</string>
                <string>mdown</string>
                <string>mdwn</string>
                <string>mkd</string>
                <string>mkdn</string>
                <string>mdtxt</string>
                <string>mdtext</string>
                <string>mmd</string>
                <string>rmd</string>
                <string>rmarkdown</string>
                <string>qmd</string>
            </array>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
                <string>io.typora.markdown</string>
            </array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>net.daringfireball.markdown</string>
            <key>UTTypeDescription</key>
            <string>Markdown Text</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.plain-text</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>md</string>
                    <string>markdown</string>
                    <string>mdown</string>
                    <string>mdwn</string>
                    <string>mkd</string>
                    <string>mkdn</string>
                    <string>mdtxt</string>
                    <string>mdtext</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>text/markdown</string>
                    <string>text/x-markdown</string>
                    <string>text/x-web-markdown</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>io.typora.markdown</string>
            <key>UTTypeDescription</key>
            <string>Markdown Text</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>net.daringfireball.markdown</string>
                <string>public.plain-text</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>mmd</string>
                    <string>rmd</string>
                    <string>rmarkdown</string>
                    <string>qmd</string>
                    <string>apib</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>text/markdown</string>
                    <string>text/x-markdown</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

rm -f "$ZIP"
(cd "$ROOT/dist" && ditto -c -k --keepParent "$APP_NAME.app" "$(basename "$ZIP")")

echo "$APP_DIR"
