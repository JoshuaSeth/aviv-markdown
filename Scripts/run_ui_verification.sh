#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift test
"$ROOT/Scripts/package_app.sh"

mkdir -p "$ROOT/dist/snapshots"
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --verify-commands
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --verify-tabs
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --verify-default-app-prompt
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --verify-layout
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --verify-minimap
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --snapshot "$ROOT/dist/snapshots/reading.png"
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --snapshot "$ROOT/dist/snapshots/editing-heading.png" --cursor "Aviv Markdown"
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --snapshot "$ROOT/dist/snapshots/editing-inline.png" --cursor "bold text"
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --snapshot "$ROOT/dist/snapshots/editing-link.png" --cursor "links"
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --snapshot "$ROOT/dist/snapshots/editing-table.png" --cursor "Heading"
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --snapshot "$ROOT/dist/snapshots/a4-format.png" --format a4
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --snapshot-print "$ROOT/dist/snapshots/a4-print-preview.png" --format a4
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --snapshot "$ROOT/dist/snapshots/zoom-out.png" --zoom 0.7818
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --snapshot "$ROOT/dist/snapshots/zoom-in.png" --zoom 0.946
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --snapshot-minimap "$ROOT/dist/snapshots/minimap-top.png" --scroll 0
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --snapshot-minimap "$ROOT/dist/snapshots/minimap-middle.png" --scroll 0.5
"$ROOT/dist/Aviv.app/Contents/MacOS/Aviv" --snapshot-minimap "$ROOT/dist/snapshots/minimap-bottom.png" --scroll 1

echo "snapshots:"
echo "$ROOT/dist/snapshots/reading.png"
echo "$ROOT/dist/snapshots/editing-heading.png"
echo "$ROOT/dist/snapshots/editing-inline.png"
echo "$ROOT/dist/snapshots/editing-link.png"
echo "$ROOT/dist/snapshots/editing-table.png"
echo "$ROOT/dist/snapshots/a4-format.png"
echo "$ROOT/dist/snapshots/a4-print-preview.png"
echo "$ROOT/dist/snapshots/zoom-out.png"
echo "$ROOT/dist/snapshots/zoom-in.png"
echo "$ROOT/dist/snapshots/minimap-top.png"
echo "$ROOT/dist/snapshots/minimap-middle.png"
echo "$ROOT/dist/snapshots/minimap-bottom.png"
