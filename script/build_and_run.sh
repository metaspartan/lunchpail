#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Lunchpail"
PRODUCT_NAME="LunchpailApp"
BUNDLE_ID="dev.lunchpail.app"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --package-path "$ROOT_DIR" --product "$PRODUCT_NAME"
BUILD_DIR="$(swift build --package-path "$ROOT_DIR" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/Resources/LunchpailApp-Info.plist" "$APP_CONTENTS/Info.plist"
chmod +x "$APP_BINARY"
codesign --force --sign - \
  --entitlements "$ROOT_DIR/Resources/lunchpail.entitlements" \
  "$APP_BINARY"
codesign --force --sign - \
  --entitlements "$ROOT_DIR/Resources/lunchpail.entitlements" \
  "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --build-only|build-only)
    echo "built $APP_BUNDLE"
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME launched successfully"
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
