#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> checking submodules"
git submodule update --init --recursive

echo "==> checking go"
if ! command -v go >/dev/null 2>&1; then
  echo "go is missing, installing with Homebrew"
  brew install go
fi

echo "==> checking xcodegen"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is missing, installing with Homebrew"
  brew install xcodegen
fi

echo "==> building core"
bash scripts/build-core.sh

echo "==> generating Xcode project"
xcodegen generate

echo "done. open Clash.xcodeproj, set your development team and App Group id, then run."
