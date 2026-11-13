#!/usr/bin/env python3
"""Read or save Blue View's Hyprland window appearance overrides."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

home = Path.home()
state = home / '.local/state/bvos/window-appearance.json'
config = home / '.config/hypr/bvos-appearance.lua'

def option(name, key):
    output = subprocess.check_output(['hyprctl', '-j', 'getoption', 'decoration:' + name], text=True, timeout=5)
    return json.loads(output)[key]

def replace(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(data)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

if sys.argv[1:] == ['status']:
    print(json.dumps({'corners': 'rounded' if option('rounding', 'int') > 0 else 'square', 'opacity': round(option('active_opacity', 'float') * 100)}))
    raise SystemExit
if len(sys.argv) != 3:
    raise SystemExit('Expected corners or opacity and a value')
key, value = sys.argv[1:]
if key == 'corners' and value in ('square', 'rounded'):
    pass
elif key == 'opacity' and value.isdigit() and int(value) in range(10, 101, 5):
    pass
else:
    raise SystemExit('Invalid setting')
try:
    values = json.loads(state.read_text())
except FileNotFoundError:
    values = {}
values[key] = value
lines = ['-- Blue View window appearance, managed by the Blue View settings window.', 'hl.config({ decoration = {']
if 'corners' in values:
    lines.append('  rounding = ' + ('12' if values['corners'] == 'rounded' else '0') + ',')
if 'opacity' in values:
    opacity = int(values['opacity']) / 100
    lines.extend([f'  active_opacity = {opacity:.2f},', f'  inactive_opacity = {opacity:.2f},'])
lines.append('} })')
old = config.read_text() if config.exists() else ''
replace(config, '\n'.join(lines) + '\n')
try:
    subprocess.run(['hyprctl', 'reload'], check=True, stdout=subprocess.DEVNULL, timeout=10)
    errors = subprocess.check_output(['hyprctl', 'configerrors'], text=True, timeout=10).strip()
    if errors:
        raise RuntimeError(errors)
except Exception:
    replace(config, old)
    subprocess.run(['hyprctl', 'reload'], check=False, stdout=subprocess.DEVNULL, timeout=10)
    raise
replace(state, json.dumps(values, indent=2) + '\n')
