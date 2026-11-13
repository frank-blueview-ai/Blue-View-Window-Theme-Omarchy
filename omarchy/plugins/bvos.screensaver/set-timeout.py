#!/usr/bin/env python3
"""Update the Omarchy screensaver idle delay without discarding other settings."""
import json
import os
from pathlib import Path
import sys
import tempfile

seconds = int(sys.argv[1])
if seconds not in (60, 150, 300, 600):
    raise SystemExit("Unsupported timeout")
path = Path.home() / ".config/omarchy/shell.json"
with path.open() as f:
    config = json.load(f)
config.setdefault("idle", {})["screensaver"] = seconds
fd, name = tempfile.mkstemp(prefix=".shell-", dir=path.parent)
try:
    os.fchmod(fd, path.stat().st_mode & 0o777)
    with os.fdopen(fd, "w") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(name, path)
finally:
    if os.path.exists(name):
        os.unlink(name)
