#!/bin/bash
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0.
#
# Blue View OS sky: orbital elements (TLE) for the space stations and the
# brightest visible satellites, from CelesTrak. Cached for 12 hours, as
# CelesTrak asks clients not to download the same data more than every 2 hours.
# Output: "# group <name>" markers followed by three-line TLE sets.

cache="${XDG_CACHE_HOME:-$HOME/.cache}/bvos"
mkdir -p "$cache"

for group in stations visual; do
  file="$cache/$group.tle"
  if [[ ! -s $file ]] || [[ -n $(find "$file" -mmin +720 2>/dev/null) ]]; then
    curl -fsS --max-time 20 "https://celestrak.org/NORAD/elements/gp.php?GROUP=${group}&FORMAT=tle" -o "$file.new" 2>/dev/null &&
      grep -q '^1 ' "$file.new" && mv -f "$file.new" "$file"
    rm -f "$file.new"
  fi
  if [[ -s $file ]]; then
    echo "# group $group"
    tr -d '\r' <"$file"
  fi
done
