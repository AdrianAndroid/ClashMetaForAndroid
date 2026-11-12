#!/usr/bin/env bash
#
# Builds the mihomo Go core as a static iOS library and wraps the device and
# simulator slices into ClashCore.xcframework.
#
# Requirements: go >= 1.21, Xcode command line tools.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build"
TAGS="${GO_TAGS:-ios,with_gvisor}"
MIN_IOS="${MIN_IOS:-16.0}"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v go >/dev/null 2>&1; then
  echo "go toolchain not found, install it with: brew install go" >&2
  exit 1
fi

if [ ! -f "$ROOT/third_party/mihomo/go.mod" ]; then
  echo "mihomo submodule is empty, run: git submodule update --init --recursive" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/device" "$OUT/simulator" "$OUT/include"

build_slice() {
  local sdk="$1"
  local arch="$2"
  local outdir="$3"
  local target="$arch-apple-ios$MIN_IOS"
  local sdk_path cc

  if [ "$sdk" = "iphonesimulator" ]; then
    target="$arch-apple-ios$MIN_IOS-simulator"
  fi

  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  cc="$(xcrun --sdk "$sdk" --find clang)"

  echo "==> building $sdk/$arch"

  (
    cd "$ROOT/core"
    CGO_ENABLED=1 \
    GOOS=ios \
    GOARCH="$arch" \
    CC="$cc" \
    CGO_CFLAGS="-isysroot $sdk_path -target $target" \
    CGO_LDFLAGS="-isysroot $sdk_path -target $target -framework Foundation -framework Security" \
    go build \
      -buildmode=c-archive \
      -tags "$TAGS" \
      -trimpath \
      -ldflags "-s -w" \
      -o "$outdir/libClashCore.a" \
      .
  )

  cp "$outdir/libClashCore.h" "$OUT/include/libClashCore.h"
}

build_slice iphoneos arm64 "$OUT/device"
build_slice iphonesimulator arm64 "$OUT/simulator"

cp "$OUT/include/libClashCore.h" "$ROOT/ClashCoreKit/ffi/libClashCore.h"
cp "$ROOT/core/bridge.h" "$ROOT/ClashCoreKit/ffi/bridge.h"

rm -rf "$ROOT/build/ClashCore.xcframework"

xcodebuild -create-xcframework \
  -library "$OUT/device/libClashCore.a" -headers "$OUT/include" \
  -library "$OUT/simulator/libClashCore.a" -headers "$OUT/include" \
  -output "$ROOT/build/ClashCore.xcframework"

echo "==> done: $ROOT/build/ClashCore.xcframework"
