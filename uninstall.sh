#!/bin/bash
# Remove the Blue View OS desktop from Omarchy.
#
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.

set -uo pipefail

hyprctl plugin unload "$HOME/.local/lib/bvos/hyprbars.so" >/dev/null 2>&1
hyprctl plugin unload "$HOME/.local/lib/bvos/bvos-snap.so" >/dev/null 2>&1

sed -i '/-- Blue View OS glass title bars and window buttons./d; /require("hypr.bvos-windows")/d' "$HOME/.config/hypr/hyprland.lua"
rm -f "$HOME/.config/hypr/bvos-windows.lua" \
  "$HOME/.local/bin/bvos-window-minimize" \
  "$HOME/.local/bin/bvos-hyprbars-build" \
  "$HOME/.local/bin/bvos-snap-build" \
  "$HOME/.config/omarchy/hooks/post-update.d/bvos-hyprbars" \
  "$HOME/.config/omarchy/hooks/post-update.d/bvos-snap"
rm -rf "$HOME/.local/lib/bvos" "$HOME/.local/share/bvos" "$HOME/.config/omarchy/plugins/bvos.screensaver"

shell_json="$HOME/.config/omarchy/shell.json"
if [[ -f $shell_json ]]; then
  tmp=$(mktemp)
  jq '.plugins = ((.plugins // []) | map(select(.id != "bvos.screensaver")))' "$shell_json" >"$tmp" && cat "$tmp" >"$shell_json"
  rm -f "$tmp"
fi

# Bring back Omarchy's terminal screensaver.
omarchy-toggle screensaver-off off

hyprctl reload >/dev/null
omarchy restart shell >/dev/null 2>&1

echo "Blue View OS desktop removed. The theme stays in ~/.config/omarchy/themes/blue-view-os;"
echo "switch themes with: omarchy theme set <name>"
