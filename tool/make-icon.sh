#!/bin/bash
# Builds Resources/Icon/AppIcon.icns from Resources/Icon/AppIcon-source.png.
# The source is full-bleed 1024 × 1024 artwork; mask-icon.swift fits it into the
# macOS icon grid, iconutil produces every size macOS asks for.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$DIR/Resources/Icon/AppIcon-source.png"
OUT="$DIR/Resources/Icon/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SWIFT="$(xcrun --find swift 2>/dev/null || true)"
if [ -z "$SWIFT" ] || ! "$SWIFT" --version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  SWIFT=/Library/Developer/CommandLineTools/usr/bin/swift
fi

"$SWIFT" "$DIR/tool/mask-icon.swift" "$SOURCE" "$WORK/master.png"

ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/master.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$WORK/master.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT"
# A small rendition for the README.
sips -Z 256 "$WORK/master.png" --out "$DIR/Resources/Icon/AppIcon-256.png" >/dev/null
echo "built: $OUT"
