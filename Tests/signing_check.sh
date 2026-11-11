#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
IDENTITIES=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/"WindowSketch Local Signing"$/ { print $2 }')
set -- $IDENTITIES
[ "$#" -eq 1 ] || { printf '%s\n' '전용 서명 인증서가 필요합니다.' >&2; exit 1; }
SIGNING_IDENTITY="$1"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/windowsketch-signing-check.XXXXXX")
trap 'rm -rf "$WORK"' 0
FIRST="$WORK/first.app"
SECOND="$WORK/second.app"
ditto 'build/윈도우스케치.app' "$FIRST"
ditto 'build/윈도우스케치.app' "$SECOND"
mkdir "$WORK/Source"
cp Source/*.swift "$WORK/Source/"
printf '\nprint("서명 검증용 두 번째 빌드입니다.")\n' >> "$WORK/Source/main.swift"
xcrun swiftc -swift-version 5 "$WORK"/Source/*.swift -o "$SECOND/Contents/MacOS/WindowSketch" \
    -target arm64-apple-macos13.0 -framework AppKit -framework ApplicationServices \
    -module-cache-path "$WORK/swift-cache" -O
if cmp -s "$FIRST/Contents/MacOS/WindowSketch" "$SECOND/Contents/MacOS/WindowSketch"; then
    printf '%s\n' '서로 다른 실행 파일을 만들지 못했습니다.' >&2
    exit 1
fi
for APP in "$FIRST" "$SECOND"; do
    codesign --force --sign "$SIGNING_IDENTITY" --keychain "$KEYCHAIN" --timestamp=none --identifier personal.windowsketch "$APP"
    codesign --verify --deep --strict "$APP"
    "$APP/Contents/MacOS/WindowSketch" --self-test
done
FIRST_REQUIREMENT=$(codesign -d -r- "$FIRST" 2>&1 | sed -n 's/^designated => //p')
SECOND_REQUIREMENT=$(codesign -d -r- "$SECOND" 2>&1 | sed -n 's/^designated => //p')
[ -n "$FIRST_REQUIREMENT" ] && [ "$FIRST_REQUIREMENT" = "$SECOND_REQUIREMENT" ]
case "$FIRST_REQUIREMENT" in
    *anchor*|*certificate*) ;;
    *) printf '%s\n' '인증서 기반 식별 규칙이 아닙니다.' >&2; exit 1 ;;
esac
FIRST_HASH=$(codesign -dvv "$FIRST" 2>&1 | sed -n 's/^CDHash=//p')
SECOND_HASH=$(codesign -dvv "$SECOND" 2>&1 | sed -n 's/^CDHash=//p')
[ -n "$FIRST_HASH" ] && [ -n "$SECOND_HASH" ] && [ "$FIRST_HASH" != "$SECOND_HASH" ]
codesign --verify --strict -R "=$FIRST_REQUIREMENT" "$SECOND"
codesign --verify --strict -R "=$SECOND_REQUIREMENT" "$FIRST"
printf '%s\n' '서로 다른 두 빌드의 코드 해시가 달라도 인증서 기반 앱 식별 규칙이 같고 상호 검증을 통과했습니다.'
printf '%s\n' "$FIRST_REQUIREMENT"
