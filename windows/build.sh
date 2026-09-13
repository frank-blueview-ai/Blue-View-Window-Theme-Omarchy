#!/bin/bash
# Blue View OS Sky for Windows: packages the web sky as a Lively Wallpaper
# wallpaper (https://www.rocksdanister.com/lively), usable as the desktop
# background and, through Lively, as the screensaver.
#
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
#
# Usage: windows/build.sh     -> dist/Blue-View-OS-Sky-Lively.zip
# Needs: bash, python3, curl, zip; chromium and ImageMagick for the thumbnail.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/dist/windows/Blue-View-OS-Sky"
ZIP="$ROOT/dist/Blue-View-OS-Sky-Lively.zip"

"$ROOT/web/build.sh" "$PACKAGE"
cp "$ROOT/windows/lively/LivelyInfo.json" "$ROOT/windows/lively/LivelyProperties.json" "$PACKAGE/"

# Thumbnail: the live page itself, at golden hour.
if [[ -f $ROOT/windows/lively/thumbnail.jpg ]]; then
  cp "$ROOT/windows/lively/thumbnail.jpg" "$PACKAGE/"
elif command -v chromium >/dev/null && command -v magick >/dev/null; then
  shot=$(mktemp -d)
  chromium --headless=new --use-angle=swiftshader --enable-unsafe-swiftshader --hide-scrollbars \
    --window-size=1920,1080 --virtual-time-budget=6000 --user-data-dir="$shot/profile" \
    --screenshot="$shot/sky.png" "file://$PACKAGE/index.html?fps=2&hour=18.5&condition=partly&satellites=0" >/dev/null 2>&1
  magick "$shot/sky.png" -resize 640x360 -quality 88 "$PACKAGE/thumbnail.jpg"
  rm -rf "$shot"
fi

rm -f "$ZIP"
(cd "$PACKAGE" && zip -qr9 "$ZIP" .)
echo "Built $ZIP"
