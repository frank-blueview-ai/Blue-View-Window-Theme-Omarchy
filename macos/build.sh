#!/bin/bash
# Blue View OS for macOS: builds "Blue View OS.app" (live sky desktop, screensaver
# and window tiling) and "Blue View Sky.saver", and packages them with the
# wallpapers and install scripts.
#
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
#
# Runs on macOS with the Xcode command line tools.
#   macos/build.sh                          -> dist/Blue-View-OS-macOS.zip (ad-hoc signed)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" macos/build.sh
#                                           -> signed with hardened runtime, ready to notarize

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/macos"
OUT="$ROOT/dist/macos"
PACKAGE="$OUT/Blue View OS"
ZIP="$ROOT/dist/Blue-View-OS-macOS.zip"
MIN_MACOS=14.0

rm -rf "$OUT"
mkdir -p "$OUT/build" "$PACKAGE"
SDK=$(xcrun --sdk macosx --show-sdk-path)

# The shared web sky, once, copied into both bundles.
"$ROOT/web/build.sh" "$OUT/build/sky" >/dev/null

# ---- Blue View OS.app ----------------------------------------------------------

APP="$PACKAGE/Blue View OS.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  xcrun swiftc -sdk "$SDK" -target "$arch-apple-macos$MIN_MACOS" -swift-version 5 -O -wmo \
    -module-name BlueViewOS "$SRC/app/BlueViewOS.swift" -o "$OUT/build/app-$arch"
done
lipo -create "$OUT/build/app-arm64" "$OUT/build/app-x86_64" -output "$APP/Contents/MacOS/BlueViewOS"
cp "$SRC/app/Info.plist" "$APP/Contents/"
cp -R "$OUT/build/sky" "$APP/Contents/Resources/sky"

# ---- Blue View Sky.saver -------------------------------------------------------

SAVER="$PACKAGE/Blue View Sky.saver"
mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"
for arch in arm64 x86_64; do
  xcrun swiftc -sdk "$SDK" -target "$arch-apple-macos$MIN_MACOS" -swift-version 5 -O -wmo \
    -module-name BlueViewSky -emit-library -Xlinker -bundle \
    -framework ScreenSaver -framework WebKit -framework AppKit \
    "$SRC/screensaver/BlueViewSkyView.swift" -o "$OUT/build/saver-$arch"
done
lipo -create "$OUT/build/saver-arm64" "$OUT/build/saver-x86_64" -output "$SAVER/Contents/MacOS/BlueViewSky"
otool -hv "$SAVER/Contents/MacOS/BlueViewSky" | grep -q BUNDLE || { echo "The screensaver is not a loadable bundle" >&2; exit 1; }
cp "$SRC/screensaver/Info.plist" "$SAVER/Contents/"
cp -R "$OUT/build/sky" "$SAVER/Contents/Resources/sky"

# Thumbnails for System Settings, from the golden hour wallpaper.
WALLPAPERS="$ROOT/windows/theme/wallpapers"
for size in "180 116 thumbnail@2x.png" "90 58 thumbnail.png"; do
  set -- $size
  sips -s format png --resampleHeight "$2" "$WALLPAPERS/2-Blue-View-Golden-Hour.jpg" --out "$OUT/build/thumb.png" >/dev/null
  sips --cropToHeightWidth "$2" "$1" "$OUT/build/thumb.png" --out "$SAVER/Contents/Resources/$3" >/dev/null
done

# ---- Sign ----------------------------------------------------------------------

xattr -cr "$APP" "$SAVER"
if [[ -n ${SIGN_IDENTITY:-} ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SAVER"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  echo "No SIGN_IDENTITY: ad-hoc signing (fine for testing; Accessibility must be granted again after each build)."
  codesign --force --sign - "$SAVER"
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
codesign --verify --deep --strict "$SAVER"

# ---- Package -------------------------------------------------------------------

mkdir -p "$PACKAGE/wallpapers"
cp "$WALLPAPERS"/*.jpg "$PACKAGE/wallpapers/"
cp "$SRC/install.sh" "$SRC/uninstall.sh" "$SRC/Install.command" "$SRC/Uninstall.command" "$SRC/README.md" "$ROOT/LICENSE" "$ROOT/NOTICE" "$PACKAGE/"
chmod +x "$PACKAGE/install.sh" "$PACKAGE/uninstall.sh" "$PACKAGE/Install.command" "$PACKAGE/Uninstall.command"

rm -f "$ZIP"
ditto -c -k --keepParent "$PACKAGE" "$ZIP"
echo "Built $ZIP"
