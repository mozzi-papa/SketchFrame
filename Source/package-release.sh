#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
APP='build/SketchFrame.app'
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
case "$VERSION" in ''|*[!0-9.]*) printf '%s\n' '올바른 버전이 필요합니다.' >&2; exit 1 ;; esac
codesign --verify --deep --strict "$APP"
ARCHIVE="sketchframe-$VERSION-arm64.zip"
/usr/bin/ditto -c -k --keepParent --norsrc "$APP" "build/$ARCHIVE"
(cd build && /usr/bin/shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
printf '배포 파일: build/%s\n체크섬: build/%s.sha256\n' "$ARCHIVE" "$ARCHIVE"
