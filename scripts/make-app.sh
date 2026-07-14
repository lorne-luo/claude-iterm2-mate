#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: make-app.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/ClaudeItermMate.app"
BUILD="$ROOT/.build/release"
BUNDLE="ClaudeItermMate_ClaudeItermMate.bundle"

echo "==> swift build -c release"
swift build -c release --package-path "$ROOT"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD/ClaudeItermMate" "$APP/Contents/MacOS/ClaudeItermMate"
cp -R "$BUILD/$BUNDLE" "$APP/Contents/Resources/$BUNDLE"

sed "s/__VERSION__/$VERSION/g" "$ROOT/scripts/Info.plist.template" \
	> "$APP/Contents/Info.plist"

echo "==> ad-hoc signing"
codesign -s - --deep --force "$APP"
codesign --verify --deep --strict "$APP"

echo "==> built $APP (version $VERSION)"
