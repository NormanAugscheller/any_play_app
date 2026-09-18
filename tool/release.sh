#!/bin/bash
# Builds AnyPlay and zips it into dist/ for sharing.
#
# IMPORTANT, and explained in the README: this archive is signed with an Apple
# Development certificate, not a Developer ID, and it is not notarized. Gatekeeper
# rejects it on another Mac. Real distribution needs a Developer ID and notarization.
# Until then, building it yourself is the honest way.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DIR/Resources/Info.plist")"
OUT="$DIR/dist"

"$DIR/build.sh"
mkdir -p "$OUT"
ARCHIVE="$OUT/AnyPlay-$VERSION.zip"
rm -f "$ARCHIVE"
# ditto rather than zip: only this keeps the signature and symlinks in the bundle intact.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$DIR/build/AnyPlay.app" "$ARCHIVE"

echo "archive: $ARCHIVE"
echo
codesign --verify --deep --strict --verbose=2 "$DIR/build/AnyPlay.app" 2>&1 | sed 's/^/  /'
echo
echo "note: not notarized. Gatekeeper blocks this archive on another Mac."
echo "See the README, section \"Distribution and Gatekeeper\"."
