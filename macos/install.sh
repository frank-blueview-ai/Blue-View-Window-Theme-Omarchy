#!/bin/bash
# Blue View OS for macOS: installs the theme.
#
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
#
#   Theme          the Blue View sky wallpaper, dark mode, blue accent and highlight colors
#   Blue View OS   menu bar app: live sky desktop, screensaver, and window tiling
#                  (Option + Shift + T; drag a tile onto another to swap)
#   Screensaver    "Blue View Sky" in System Settings
#
# Usage, from the unzipped folder:   ./install.sh            (or double-click "Install.command")
#   --theme-only    only the wallpaper and colors

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPPORT="$HOME/Library/Application Support/BlueViewOS"
APP_NAME="Blue View OS.app"
SAVER_NAME="Blue View Sky.saver"
THEME_ONLY=0
[[ ${1:-} == "--theme-only" ]] && THEME_ONLY=1

step() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
problem() { printf '    \033[33m! %s\033[0m\n' "$*"; }

OK=()
FAILED=()
part() { if "$2"; then OK+=("$1"); else FAILED+=("$1"); fi; }

[[ $(uname) == Darwin ]] || { echo "This installer is for macOS." >&2; exit 1; }
MACOS=$(sw_vers -productVersion)
MAJOR=${MACOS%%.*}
MINOR=$(echo "$MACOS" | cut -d. -f2)
MINOR=${MINOR:-0}
if (( MAJOR < 14 )); then
  echo "Blue View OS needs macOS 14 Sonoma or later (this Mac has $MACOS)." >&2
  exit 1
fi

echo "Blue View OS for macOS $MACOS"

install_theme() {
  step "Applying the Blue View OS theme"
  mkdir -p "$SUPPORT/Wallpapers"
  cp "$HERE"/wallpapers/*.jpg "$SUPPORT/Wallpapers/" || return 1

  # The wallpaper: golden hour, the view the live sky desktop fades in over.
  local wallpaper="$SUPPORT/Wallpapers/2-Blue-View-Golden-Hour.jpg"
  if osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$wallpaper\"" >/dev/null 2>&1; then
    note "Wallpaper set on every display (other Spaces: System Settings → Wallpaper → Show on all Spaces)."
  else
    problem "Couldn't set the wallpaper. Allow Terminal to control System Events when asked, then run this again."
  fi

  # Dark mode, the logo's blue as the accent, and a Blue View blue highlight.
  osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null 2>&1 ||
    problem "Couldn't turn on dark mode (System Settings → Appearance)."
  defaults write -g AppleAccentColor -int 4
  defaults write -g AppleHighlightColor -string "0.219608 0.713725 1.000000 Other"
  # Tell running apps the colors changed, so they don't need a restart.
  osascript -l JavaScript -e 'ObjC.import("Foundation"); const c = $.NSDistributedNotificationCenter.defaultCenter; ["AppleAquaColorVariantChanged", "AppleColorPreferencesChangedNotification"].forEach(n => c.postNotificationNameObjectUserInfoDeliverImmediately(n, $(), $(), true))' >/dev/null 2>&1
  note "Dark mode with Blue View blue accents."
  return 0
}

install_app() {
  step "Installing the Blue View OS app"
  [[ -d $HERE/$APP_NAME ]] || { problem "$APP_NAME is missing from this folder."; return 1; }

  osascript -e 'tell application "Blue View OS" to quit' >/dev/null 2>&1
  pkill -x BlueViewOS 2>/dev/null
  sleep 1

  local target="/Applications"
  if ! { rm -rf "$target/$APP_NAME" 2>/dev/null && ditto "$HERE/$APP_NAME" "$target/$APP_NAME" 2>/dev/null; }; then
    target="$HOME/Applications"
    mkdir -p "$target"
    rm -rf "$target/$APP_NAME"
    ditto "$HERE/$APP_NAME" "$target/$APP_NAME" || return 1
  fi
  xattr -dr com.apple.quarantine "$target/$APP_NAME" 2>/dev/null

  # On macOS 26.4 and later, web views inside third-party screensavers go blank,
  # so the app shows the screensaver itself there.
  if (( MAJOR > 26 || (MAJOR == 26 && MINOR >= 4) )); then
    defaults write ai.blueview.os ScreensaverMinutes -int 5
    USE_APP_SCREENSAVER=1
  fi

  open "$target/$APP_NAME"
  note "Installed in $target. It's in the menu bar (the two ovals) and opens at login."
  note "For window tiling, allow \"Blue View OS\" when macOS asks about Accessibility"
  note "(System Settings → Privacy & Security → Accessibility)."
  return 0
}

install_screensaver() {
  step "Installing the Blue View Sky screensaver"
  [[ -d $HERE/$SAVER_NAME ]] || { problem "$SAVER_NAME is missing from this folder."; return 1; }
  mkdir -p "$HOME/Library/Screen Savers"
  rm -rf "$HOME/Library/Screen Savers/$SAVER_NAME"
  ditto "$HERE/$SAVER_NAME" "$HOME/Library/Screen Savers/$SAVER_NAME" || return 1
  xattr -dr com.apple.quarantine "$HOME/Library/Screen Savers/$SAVER_NAME" 2>/dev/null
  killall legacyScreenSaver 2>/dev/null

  if [[ ${USE_APP_SCREENSAVER:-0} == 1 ]]; then
    note "On macOS $MACOS the Blue View OS app shows the screensaver after 5 minutes idle"
    note "(change it from the menu bar icon → Screensaver)."
    return 0
  fi

  # Select it. macOS 14 and later keep this in an undocumented wallpaper store, so
  # it's best effort; System Settings → Wallpaper → Screen Saver always works.
  local store="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
  local saver_url="file://$(printf '%s' "$HOME/Library/Screen Savers/$SAVER_NAME" | sed 's/ /%20/g')"
  local config
  config=$(mktemp) && plutil -create binary1 "$config" && plutil -insert module -dictionary "$config" &&
    plutil -insert module.relative -string "$saver_url" "$config"
  local selected=0
  if [[ -f $store ]]; then
    local encoded
    encoded=$(base64 -i "$config")
    cp "$store" "$SUPPORT/wallpaper-store-backup.plist" 2>/dev/null
    for root in AllSpacesAndDisplays SystemDefault; do
      plutil -replace "$root.Idle.Content.Choices" -json '[{"Provider":"com.apple.wallpaper.choice.screen-saver","Files":[]}]' "$store" 2>/dev/null &&
        plutil -replace "$root.Idle.Content.Choices.0.Configuration" -data "$encoded" "$store" 2>/dev/null && selected=1
    done
    killall WallpaperAgent 2>/dev/null
  fi
  rm -f "$config"

  if (( selected )); then
    note "Selected as your screensaver."
  else
    note "Pick it in System Settings → Wallpaper → Screen Saver (under Other)."
  fi
  return 0
}

part "Theme" install_theme
if (( ! THEME_ONLY )); then
  part "Blue View OS app" install_app
  part "Screensaver" install_screensaver
fi

printf '\n\033[1mSummary\033[0m\n'
for p in ${OK[@]+"${OK[@]}"}; do printf '  \033[32m[ok]\033[0m      %s\n' "$p"; done
for p in ${FAILED[@]+"${FAILED[@]}"}; do printf '  \033[33m[failed]\033[0m  %s\n' "$p"; done
echo
echo "To remove Blue View OS later, run ./uninstall.sh from this folder."
