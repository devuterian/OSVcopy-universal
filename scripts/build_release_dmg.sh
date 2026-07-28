#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Bundle/Info.plist")"

"$ROOT/build_osvcopy_app.sh"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$ROOT/dist/OSVcopy.app" "$STAGE/OSVcopy.app"

mkdir -p "$ROOT/dist"
DMG="$ROOT/dist/OSVcopy-${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "OSVcopy ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

echo ""
echo "DMG: $DMG"
