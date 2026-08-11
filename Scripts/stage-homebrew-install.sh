#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <prefix>" >&2
  exit 2
fi

INSTALL_PREFIX="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

swift build --package-path "$ROOT_DIR" --configuration release --product lunchpail
swift build --package-path "$ROOT_DIR" --configuration release --product lunchpail-metal-probe
swift build --package-path "$ROOT_DIR" --configuration release --product LunchpailMetalShim
BUILD_DIR="$(swift build --package-path "$ROOT_DIR" --configuration release --show-bin-path)"

mkdir -p "$INSTALL_PREFIX/bin" "$INSTALL_PREFIX/libexec/lunchpail"
install -m 0755 "$BUILD_DIR/lunchpail" "$INSTALL_PREFIX/bin/lunchpail"
ditto "$BUILD_DIR/Lunchpail_LunchpailAPI.bundle" "$INSTALL_PREFIX/bin/Lunchpail_LunchpailAPI.bundle"
install -m 0755 "$BUILD_DIR/lunchpail-metal-probe" "$INSTALL_PREFIX/libexec/lunchpail/lunchpail-metal-probe"
install -m 0755 "$BUILD_DIR/libLunchpailMetalShim.dylib" "$INSTALL_PREFIX/libexec/lunchpail/libLunchpailMetalShim.dylib"

codesign --force --sign - "$INSTALL_PREFIX/libexec/lunchpail/lunchpail-metal-probe"
codesign --force --sign - "$INSTALL_PREFIX/libexec/lunchpail/libLunchpailMetalShim.dylib"
codesign --force --sign - --entitlements "$ROOT_DIR/Resources/lunchpail.entitlements" "$INSTALL_PREFIX/bin/lunchpail"
