#!/usr/bin/env python3
"""Manage individual and remembered application opacity for Blue View."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

home = Path.home()
state_path = home / '.local/state/bvos/window-opacity.json'
config_path = home / '.config/hypr/bvos-opacity-apps.lua'

def call(*args):
    return subprocess.check_output(args, text=True, timeout=8).strip()

def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(text)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def read():
    try:
        s = json.loads(state_path.read_text())
        if not isinstance(s, dict):
            raise ValueError('Invalid opacity state')
        return s
    except FileNotFoundError:
        return {'apps': {}, 'windows': {}}

def client(address, pid):
    if not re.fullmatch(r'0x[0-9a-fA-F]+', address) or not str(pid).isdigit():
        raise ValueError('Invalid window identity')
    for w in json.loads(call('hyprctl', '-j', 'clients')):
        if w.get('address') == address and w.get('pid') == int(pid):
            return w
    raise ValueError('Window has closed')

def apply(address, value):
    for prop in ('opacity', 'opacity_inactive', 'opacity_override', 'opacity_inactive_override'):
        v = ('0' if prop.endswith('_override') else '1') if value is None else ('1' if prop.endswith('_override') else str(value / 100))
        lua = 'hl.dsp.window.set_prop({window="address:' + address + '",prop="' + prop + '",value="' + v + '"})'
        result = call('hyprctl', 'dispatch', lua)
        if result != 'ok':
            raise RuntimeError(result)

def update_rules(apps):
    lines = ['-- Blue View remembered application opacity. Managed automatically.']
    for app, value in sorted(apps.items()):
        pattern = '^' + re.escape(app) + '$'
        quoted = json.dumps(pattern, ensure_ascii=False)
        alpha = int(value) / 100
        lines.append('o.window({ class = ' + quoted + ' }, { opacity = "' + f'{alpha:.2f} override {alpha:.2f} override' + '" })')
    previous = config_path.read_text() if config_path.exists() else ''
    atomic(config_path, '\n'.join(lines) + '\n')
    try:
        call('hyprctl', 'reload')
        errors = call('hyprctl', 'configerrors')
        if errors:
            raise RuntimeError(errors)
    except Exception:
        atomic(config_path, previous)
        call('hyprctl', 'reload')
        raise

cmd = sys.argv[1]
s = read()
apps = s.setdefault('apps', {})
windows = s.setdefault('windows', {})
if cmd == 'open':
    w = json.loads(call('hyprctl', '-j', 'activewindow'))
    address, pid = w.get('address', ''), str(w.get('pid', ''))
    client(address, pid)
    app = w.get('class', '')
    if not isinstance(app, str) or not app or len(app) > 256 or any(ord(c) < 32 for c in app):
        raise ValueError('Application has no usable window class')
    item = windows.get(address, {})
    val = item.get('value') if item.get('pid') == pid else None
    if val is None:
        val = apps.get(app)
    if val is None:
        val = round(json.loads(call('hyprctl', '-j', 'getoption', 'decoration:active_opacity'))['float'] * 100)
    call('omarchy-shell', 'bvos-window-opacity', 'show', address, pid, app, str(val), 'yes' if app in apps else 'no')
elif cmd in ('set', 'remember', 'reset'):
    address, pid = sys.argv[2:4]
    w = client(address, pid)
    app = w.get('class', '')
    if cmd == 'remember' and app == 'org.quickshell' and sys.argv[5] == 'yes':
        raise ValueError('Cannot remember settings for shared shell windows')
    if cmd == 'set':
        value = int(sys.argv[4])
        if value not in range(10, 101, 5):
            raise ValueError('Invalid opacity')
        apply(address, value)
        windows[address] = {'pid': pid, 'value': value}
        if sys.argv[5] == 'yes':
            apps[app] = value
            update_rules(apps)
            apply(address, value)
    elif cmd == 'remember':
        value = int(sys.argv[4])
        if value not in range(10, 101, 5) or sys.argv[5] not in ('yes', 'no'):
            raise ValueError('Invalid setting')
        if sys.argv[5] == 'yes':
            apps[app] = value
        else:
            apps.pop(app, None)
        update_rules(apps)
        apply(address, value)
        windows[address] = {'pid': pid, 'value': value}
    else:
        apps.pop(app, None)
        windows.pop(address, None)
        update_rules(apps)
        apply(address, None)
    # Keep only entries for currently existing windows, preventing stale reuse.
    live = {(x.get('address'), str(x.get('pid'))) for x in json.loads(call('hyprctl', '-j', 'clients'))}
    s['windows'] = {a: v for a, v in windows.items() if (a, v.get('pid')) in live}
    atomic(state_path, json.dumps(s, indent=2, ensure_ascii=False) + '\n')
else:
    raise SystemExit('Invalid command')
