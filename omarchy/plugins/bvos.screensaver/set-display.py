#!/usr/bin/env python3
"""Save BlueView display options."""
import json
import os
from pathlib import Path
import sys
import tempfile

options = {"clockFormat": ("12", "24"), "skyTime": ("live", "day", "sunset", "night"), "panelTheme": ("light", "dark"), "opacity": tuple(str(n) for n in range(10, 101, 5))}
if len(sys.argv) != 3 or sys.argv[1] not in options or sys.argv[2] not in options[sys.argv[1]]:
    raise SystemExit("Unsupported setting")
path = Path.home() / ".local/state/bvos/display.json"
path.parent.mkdir(parents=True, exist_ok=True)
try:
    settings = json.loads(path.read_text())
    if not isinstance(settings, dict):
        raise ValueError("Expected an object")
except FileNotFoundError:
    settings = {}
settings[sys.argv[1]] = sys.argv[2]
fd, temporary = tempfile.mkstemp(prefix=".display-", dir=path.parent)
try:
    with os.fdopen(fd, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    os.replace(temporary, path)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
