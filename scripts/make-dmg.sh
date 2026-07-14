#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: make-dmg.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/ClaudeItermMate.app"
DMG="$ROOT/dist/ClaudeItermMate-$VERSION.dmg"
STAGE="$ROOT/dist/dmg-stage"

test -d "$APP" || { echo "missing $APP — run make-app.sh first" >&2; exit 1; }

echo "==> staging"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/ClaudeItermMate.app"
ln -s /Applications "$STAGE/Applications"

echo "==> hdiutil create"
hdiutil create -volname "ClaudeItermMate" \
	-srcfolder "$STAGE" -ov -format UDZO "$DMG"

rm -rf "$STAGE"
echo "==> built $DMG"
