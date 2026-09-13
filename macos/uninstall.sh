#!/bin/bash
# Blue View OS for macOS: removes the app, the screensaver and the Blue View colors.
#
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
#
# Dark mode and the wallpaper stay as they are; change them in System Settings.

set -uo pipefail

SUPPORT="$HOME/Library/Application Support/BlueViewOS"
APP_NAME="Blue View OS.app"
SAVER_NAME="Blue View Sky.saver"

echo "Removing Blue View OS"

osascript -e 'tell application "Blue View OS" to quit' >/dev/null 2>&1
pkill -x BlueViewOS 2>/dev/null
sleep 1

for dir in /Applications "$HOME/Applications"; do
  if [[ -d $dir/$APP_NAME ]]; then
    rm -rf "$dir/$APP_NAME" && echo "    Removed $dir/$APP_NAME"
  fi
done
defaults delete ai.blueview.os >/dev/null 2>&1

if [[ -d "$HOME/Library/Screen Savers/$SAVER_NAME" ]]; then
  rm -rf "$HOME/Library/Screen Savers/$SAVER_NAME" && echo "    Removed the Blue View Sky screensaver"
  killall legacyScreenSaver 2>/dev/null
fi

# Back to the default accent and highlight colors.
defaults delete -g AppleAccentColor >/dev/null 2>&1
defaults delete -g AppleHighlightColor >/dev/null 2>&1
osascript -l JavaScript -e 'ObjC.import("Foundation"); const c = $.NSDistributedNotificationCenter.defaultCenter; ["AppleAquaColorVariantChanged", "AppleColorPreferencesChangedNotification"].forEach(n => c.postNotificationNameObjectUserInfoDeliverImmediately(n, $(), $(), true))' >/dev/null 2>&1

# Keep the setup copy this may be running from; remove the rest.
if [[ -d $SUPPORT ]]; then
  find "$SUPPORT" -mindepth 1 -maxdepth 1 ! -name Setup -exec rm -rf {} +
fi

echo "Blue View OS is removed. Pick a new screensaver in System Settings → Wallpaper → Screen Saver."
