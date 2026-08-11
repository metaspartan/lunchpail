#!/bin/sh
set -eu

BUILD_DIR=${1:-.build/debug}
SHIM="$BUILD_DIR/libLunchpailMetalShim.dylib"
PROBE="$BUILD_DIR/lunchpail-metal-probe"

test -f "$SHIM"
test -x "$PROBE"
lipo "$SHIM" -verify_arch arm64
lipo "$PROBE" -verify_arch arm64
codesign --verify --strict "$SHIM"

if strings "$SHIM" | grep -Eq \
  'GPU_HOOK_TIME_SCALE|mach_absolute_time|clock_gettime|gettimeofday|MESH_FALLBACK|IGNORE_ARGTYPE|SYNC_COMPUTE|LUME_METAL_FEATURE_PROFILE|featureProfile|LUME_METAL_FAMILY_MAX'; then
  echo "unexpected broad or timing-related hook found in Metal shim" >&2
  exit 1
fi

echo "Metal artifacts verified"
