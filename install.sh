#!/bin/bash
# Blue View OS desktop for Omarchy: glass title bars, the Blue View OS theme,
# and the above-the-clouds screensaver.
#
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
#
# Usage: ./install.sh [--no-theme]

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY_THEME=1
[[ ${1:-} == "--no-theme" ]] && APPLY_THEME=0

step() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
backup() { [[ -e $1 ]] && cp "$1" "$1.bak.$(date +%s)"; return 0; }

command -v omarchy >/dev/null || { echo "Blue View OS desktop needs Omarchy (https://omarchy.org)." >&2; exit 1; }
for tool in jq curl git make g++ pkg-config hyprctl; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done
[[ -f /usr/include/hyprland/src/version.h ]] || { echo "Hyprland headers not found in /usr/include/hyprland." >&2; exit 1; }

step "Installing commands"
install -Dm755 "$SRC/bin/bvos-window-minimize" "$HOME/.local/bin/bvos-window-minimize"
install -Dm755 "$SRC/bin/bvos-hyprbars-build" "$HOME/.local/bin/bvos-hyprbars-build"

step "Building the title-bar plugin (hyprbars + Blue View OS button alignment)"
install -Dm644 "$SRC/hyprbars/hyprbars-button-align.patch" "$HOME/.local/share/bvos/hyprbars-button-align.patch"
"$HOME/.local/bin/bvos-hyprbars-build" --force

step "Configuring Hyprland window chrome"
install -Dm644 "$SRC/hypr/bvos-windows.lua" "$HOME/.config/hypr/bvos-windows.lua"
if ! grep -q 'require("hypr.bvos-windows")' "$HOME/.config/hypr/hyprland.lua"; then
  backup "$HOME/.config/hypr/hyprland.lua"
  printf '\n-- Blue View OS glass title bars and window buttons.\nrequire("hypr.bvos-windows")\n' >>"$HOME/.config/hypr/hyprland.lua"
fi

step "Installing the update hook (rebuilds the plugin after Hyprland updates)"
install -Dm755 "$SRC/hooks/post-update.d/bvos-hyprbars" "$HOME/.config/omarchy/hooks/post-update.d/bvos-hyprbars"

step "Installing brand fonts (Geist, Manrope, Inter)"
fonts="$HOME/.local/share/fonts/bvos"
mkdir -p "$fonts"
declare -A FONT_URLS=(
  [Geist-Variable.ttf]="https://github.com/google/fonts/raw/main/ofl/geist/Geist%5Bwght%5D.ttf"
  [Manrope-Variable.ttf]="https://github.com/google/fonts/raw/main/ofl/manrope/Manrope%5Bwght%5D.ttf"
  [Inter-Variable.ttf]="https://github.com/google/fonts/raw/main/ofl/inter/Inter%5Bopsz,wght%5D.ttf"
)
for name in "${!FONT_URLS[@]}"; do
  [[ -s $fonts/$name ]] || curl -fsSL "${FONT_URLS[$name]}" -o "$fonts/$name" || echo "Could not download $name (the screensaver falls back to system fonts)."
done
fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true

step "Installing the screensaver plugin"
plugin="$HOME/.config/omarchy/plugins/bvos.screensaver"
mkdir -p "$plugin"
cp -r "$SRC/omarchy/plugins/bvos.screensaver/." "$plugin/"
chmod +x "$plugin/weather.sh" "$plugin/satellites.sh"
rm -f "$plugin/clouds.frag"   # replaced by sky.glsl in newer versions
if [[ -x /usr/lib/qt6/bin/qsb ]]; then
  /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -DSKY_PASS -o "$plugin/sky.frag.qsb" "$plugin/sky.glsl"
  /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -DCLOUD_PASS -o "$plugin/clouds.frag.qsb" "$plugin/sky.glsl"
fi

shell_json="$HOME/.config/omarchy/shell.json"
if [[ -f $shell_json ]] && ! jq -e '.plugins // [] | map(.id) | index("bvos.screensaver")' "$shell_json" >/dev/null; then
  backup "$shell_json"
  tmp=$(mktemp)
  jq '.plugins = ((.plugins // []) + [{"id": "bvos.screensaver"}])' "$shell_json" >"$tmp" && cat "$tmp" >"$shell_json"
  rm -f "$tmp"
fi

# The Blue View OS screensaver replaces Omarchy's terminal screensaver.
omarchy-toggle screensaver-off on

step "Installing the Blue View OS theme"
mkdir -p "$HOME/.config/omarchy/themes/blue-view-os"
cp -r "$SRC/omarchy/themes/blue-view-os/." "$HOME/.config/omarchy/themes/blue-view-os/"
(( APPLY_THEME )) && omarchy theme set blue-view-os

step "Loading everything"
hyprctl plugin load "$HOME/.local/lib/bvos/hyprbars.so" >/dev/null 2>&1 || true
hyprctl reload >/dev/null
omarchy restart shell >/dev/null 2>&1 || true

errors=$(hyprctl configerrors)
if [[ -n ${errors// /} ]]; then
  echo "Hyprland reported config errors:" >&2
  echo "$errors" >&2
  exit 1
fi

cat <<'DONE'

Blue View OS desktop is installed.

  Window buttons   left: minimize, maximize, float   right: close
  Minimized tray   SUPER + M
  Screensaver      starts after idle.screensaver seconds (~/.config/omarchy/shell.json)
  Live desktop     omarchy-shell bvos-screensaver desktop <on|off>
  Preview it       omarchy-shell bvos-screensaver preview live now
DONE
