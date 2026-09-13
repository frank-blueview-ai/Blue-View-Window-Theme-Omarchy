#!/bin/bash
# Blue View OS for macOS: one-command setup.
#
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
#
# In Terminal:
#   curl -fsSL https://raw.githubusercontent.com/frank-blueview-ai/Blue-View-Window-Theme-Omarchy/main/macos/get.sh | bash
#
# Downloads the newest Blue View OS for macOS release from GitHub, unpacks it, and
# runs its installer. The unpacked copy stays in
# ~/Library/Application Support/BlueViewOS/Setup, with uninstall.sh, for later.

set -euo pipefail

REPO="frank-blueview-ai/Blue-View-Window-Theme-Omarchy"
ASSET="Blue-View-OS-macOS.zip"
SETUP="$HOME/Library/Application Support/BlueViewOS/Setup"

echo "Blue View OS for macOS"
echo "    Finding the newest release..."
# Newest release first (test releases included) that has the macOS download.
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases" |
  /usr/bin/python3 -c 'import json, sys
for release in json.load(sys.stdin):
    for asset in release.get("assets", []):
        if asset["name"] == sys.argv[1]:
            print(asset["browser_download_url"]); sys.exit(0)' "$ASSET") || true
[[ -n ${URL:-} ]] || { echo "No release with $ASSET was found at https://github.com/$REPO/releases" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "    Downloading..."
curl -fsSL "$URL" -o "$TMP/$ASSET"

rm -rf "$SETUP"
mkdir -p "$SETUP"
ditto -x -k "$TMP/$ASSET" "$TMP/unpacked"
# The zip holds one folder, "Blue View OS".
FOLDER=$(find "$TMP/unpacked" -name install.sh -maxdepth 2 -exec dirname {} \; | head -1)
[[ -n $FOLDER ]] || { echo "The download doesn't contain install.sh." >&2; exit 1; }
ditto "$FOLDER" "$SETUP"

# stdin is this script when piped from curl; give the installer the terminal instead.
bash "$SETUP/install.sh" </dev/tty
echo
echo "Setup files are kept in $SETUP. To remove Blue View OS later, run uninstall.sh there."
