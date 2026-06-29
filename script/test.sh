#!/usr/bin/env bash
# Runs the Bugu unit tests. XCTest ships with Xcode, not the bare Command Line
# Tools, so point DEVELOPER_DIR at a full Xcode if the active toolchain lacks it.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! xcrun --find xctest >/dev/null 2>&1; then
  if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  else
    echo "XCTest not found. Install Xcode, or run: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
  fi
fi

exec swift test "$@"
