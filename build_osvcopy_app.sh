#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# 기본 아이콘: 저장소 Bundle/OSVcopy.icns (다른 경로면 ICNS_SRC=/path/to/app.icns)
DEFAULT_ICNS="$ROOT/Bundle/OSVcopy.icns"
ICNS_SRC="${ICNS_SRC:-$DEFAULT_ICNS}"

if [[ ! -f "$ICNS_SRC" ]]; then
  echo "오류: icns 파일이 없습니다: $ICNS_SRC" >&2
  exit 1
fi

echo "swift build (release)…"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/OSVcopy"
if [[ ! -f "$BIN" ]]; then
  echo "오류: 빌드 산출물 없음: $BIN" >&2
  exit 1
fi

APP="$ROOT/dist/OSVcopy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/OSVcopy"
chmod +x "$APP/Contents/MacOS/OSVcopy"
cp "$ICNS_SRC" "$APP/Contents/Resources/OSVcopy.icns"
cp "$ROOT/Bundle/Info.plist" "$APP/Contents/Info.plist"

echo ""
echo "완료: $APP"

if ditto "$APP" "/Applications/OSVcopy.app" 2>/dev/null; then
  echo "응용 프로그램에 설치: /Applications/OSVcopy.app"
else
  echo "참고: /Applications 에 복사하려면 권한이 필요할 수 있습니다:"
  echo "  ditto \"$APP\" \"/Applications/OSVcopy.app\""
fi
