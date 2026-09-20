#!/bin/bash
# Runs the unit tests.
#
# The tests use swift-testing. With a full Xcode, `swift test` finds it on its own.
# With only the Command Line Tools installed, the framework is there but not on the
# search path — so the paths are passed explicitly.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

SWIFT="$(xcrun --find swift 2>/dev/null || true)"
EXTRA=()
if [ -z "$SWIFT" ] || ! "$SWIFT" --version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  SWIFT=/Library/Developer/CommandLineTools/usr/bin/swift
  FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  LIBS=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
  EXTRA=(-Xswiftc -F -Xswiftc "$FRAMEWORKS"
         -Xlinker -F -Xlinker "$FRAMEWORKS"
         -Xlinker -rpath -Xlinker "$FRAMEWORKS"
         -Xlinker -rpath -Xlinker "$LIBS")
fi

# bash 3.2 ships with macOS, and there an empty array counts as unset: with
# `set -u`, "${EXTRA[@]}" then aborts the script. The +-form expands to nothing
# when the array is empty instead.
"$SWIFT" test --package-path "$DIR" ${EXTRA[@]+"${EXTRA[@]}"} "$@"
