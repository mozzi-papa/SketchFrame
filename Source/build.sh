#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
IDENTITIES=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/"WindowSketch Local Signing"$/ { print $2 }')
set -- $IDENTITIES
if [ "$#" -ne 1 ]; then
    printf '%s\n' '전용 서명 인증서가 필요합니다. sh Source/setup-signing.sh로 한 번 등록해 주세요. 임시 서명으로 빌드하지 않습니다.' >&2
    exit 1
fi
SIGNING_IDENTITY="$1"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/windowsketch-build.XXXXXX")
trap 'rm -rf "$WORK"' 0
APP="$WORK/SketchFrame.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Source/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
xcrun swiftc -swift-version 5 Source/*.swift -o "$APP/Contents/MacOS/WindowSketch" \
    -target arm64-apple-macos13.0 -framework AppKit -framework ApplicationServices \
    -module-cache-path "$WORK/swift-cache" -O
codesign --force --sign "$SIGNING_IDENTITY" --keychain "$KEYCHAIN" --timestamp=none --identifier personal.windowsketch "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/WindowSketch" --self-test
DEST="build/SketchFrame.app"
LEGACY="build/윈도우스케치.app"
for EXISTING in "$DEST" "$LEGACY"; do
if [ -e "$EXISTING" ]; then
    RUNNING=$(pgrep -f "$PWD/$EXISTING/Contents/MacOS/WindowSketch" || true)
    if [ -n "$RUNNING" ]; then
        printf '%s\n' '실행 중인 SketchFrame을 메뉴에서 종료한 뒤 다시 빌드해 주세요.' >&2
        exit 1
    fi
fi
done
mkdir -p build
if [ -d "$LEGACY" ] && [ ! -e "$DEST" ]; then mv "$LEGACY" "$DEST"; fi
ditto "$APP" "$DEST"
codesign --verify --deep --strict "$DEST"
# 최종 경로를 등록해 Finder가 실행 파일 위치를 정확히 읽도록 합니다.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$DEST"
printf '앱 생성: %s/%s\n' "$PWD" "$DEST"
