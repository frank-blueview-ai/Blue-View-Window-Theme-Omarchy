#!/bin/bash
# Blue View OS for Windows 11:
#   - the live sky as a Lively Wallpaper wallpaper (https://www.rocksdanister.com/lively),
#     usable as the desktop background and, through Lively, as the screensaver
#   - the Windows 11 theme: installer, wallpapers and app settings, plus a
#     double-click .deskthemepack with just the wallpapers and colors
#
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
#
# Usage: windows/build.sh
#   -> dist/Blue-View-OS-Sky-Lively.zip
#   -> dist/Blue-View-OS-Windows-11-Theme.zip
#   -> dist/Blue-View-OS.deskthemepack   (needs the Python "cabarchive" package; set PYTHON to its interpreter)
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

# ---- Windows 11 theme ----------------------------------------------------------

THEME_SRC="$ROOT/windows/theme"
THEME_PACKAGE="$ROOT/dist/windows/Blue-View-OS-Windows-11-Theme"
THEME_ZIP="$ROOT/dist/Blue-View-OS-Windows-11-Theme.zip"

rm -rf "$THEME_PACKAGE"
mkdir -p "$THEME_PACKAGE/wallpapers"
cp "$THEME_SRC"/{Install.cmd,Uninstall.cmd,install.ps1,uninstall.ps1,common.ps1,windhawk-mod.ps1,mica-for-everyone.json,translucenttb.json} "$THEME_PACKAGE/"
cp "$THEME_SRC/Blue View OS.theme.in" "$THEME_PACKAGE/"
mkdir -p "$THEME_PACKAGE/tiling" && cp "$THEME_SRC/tiling/BlueViewTiling.cs" "$THEME_PACKAGE/tiling/"
cp "$THEME_SRC"/wallpapers/*.jpg "$THEME_PACKAGE/wallpapers/"
cp "$ROOT/windows/README.md" "$ROOT/LICENSE" "$ROOT/NOTICE" "$THEME_PACKAGE/"

# Files at the top of the zip: Windows' "Extract All" already makes a folder for it.
rm -f "$THEME_ZIP"
(cd "$THEME_PACKAGE" && zip -qr9 "$THEME_ZIP" .)
echo "Built $THEME_ZIP"

# The .deskthemepack is a CAB with the theme at the root and the wallpapers in
# DesktopBackground\, which Windows unpacks to its own themes folder.
PYTHON=${PYTHON:-python3}
if "$PYTHON" -c "import cabarchive" 2>/dev/null; then
  "$PYTHON" - "$THEME_SRC" "$ROOT/dist/Blue-View-OS.deskthemepack" <<'PY'
import pathlib, re, sys
from cabarchive import CabArchive, CabFile

src, out = pathlib.Path(sys.argv[1]), sys.argv[2]
template = (src / "Blue View OS.theme.in").read_text()
lines = [l for l in template.replace("{{WALLPAPERS}}", "DesktopBackground").splitlines() if not re.match(r"^\s*;", l)]
theme = ("\r\n".join(lines).strip() + "\r\n").encode("utf-16")

archive = CabArchive()
archive["Blue View OS.theme"] = CabFile(theme)
for jpg in sorted((src / "wallpapers").glob("*.jpg")):
    archive["DesktopBackground\\" + jpg.name] = CabFile(jpg.read_bytes())
pathlib.Path(out).write_bytes(archive.save(compress=True))
print("Built " + out)
PY
else
  echo "Skipped the .deskthemepack: the Python cabarchive package is not installed."
fi
