#!/bin/bash
# Builds AnyPlay.app. One command, no Xcode project needed.
#
# The app always lands at build/AnyPlay.app with the same bundle ID and is signed
# with your development certificate if you have one. macOS ties the Screen Recording
# and Accessibility permissions to that identity: with an ad-hoc signature it
# remembers the hash of the binary instead, which changes with every build — and the
# permissions would have to be granted again each time.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/build/AnyPlay.app"
BUNDLE_ID="com.normanaugscheller.anyplay"
CONFIG="${CONFIG:-release}"

# After an Xcode update, swiftc refuses to run until the Xcode license is accepted
# again. The Command Line Tools have their own, already accepted license.
SWIFT="$(xcrun --find swift 2>/dev/null || true)"
if [ -z "$SWIFT" ] || ! "$SWIFT" --version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  SWIFT=/Library/Developer/CommandLineTools/usr/bin/swift
  echo "note: Xcode toolchain unavailable, building with the Command Line Tools." >&2
fi

"$SWIFT" build -c "$CONFIG" --package-path "$DIR" --product AnyPlay
BIN="$("$SWIFT" build -c "$CONFIG" --package-path "$DIR" --show-bin-path)/AnyPlay"
[ -x "$BIN" ] || { echo "binary missing: $BIN" >&2; exit 1; }

# Build first, replace afterwards — the other way round, a failed build leaves no
# working app behind at all.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/AnyPlay"
cp "$DIR/Resources/Icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
for lproj in "$DIR"/Resources/*.lproj; do
  cp -R "$lproj" "$APP/Contents/Resources/"
done

IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
else
  echo "warning: no Apple Development certificate found, signing ad hoc." >&2
  echo "         Permissions will have to be granted again after every build." >&2
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

echo "built: $APP"
