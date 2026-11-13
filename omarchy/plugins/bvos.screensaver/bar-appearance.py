#!/usr/bin/env python3
"""Adjust bar background alpha and its monochrome icon/text color."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import tomllib

home = Path.home()
path = home / '.config/omarchy/shell.toml'
shell = home / '.config/omarchy/shell.json'
hypr = home / '.config/hypr/bvos-bar-glass.lua'
colors = {'theme': None, 'bright': '#ffffff', 'blue': '#8edbff', 'green': '#b9e79b'}

def atomic(p, data):
    p.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.' + p.name, dir=p.parent)
    try:
        with os.fdopen(fd, 'w') as f: f.write(data)
        os.replace(name, p)
    finally:
        if os.path.exists(name): os.unlink(name)

def read():
    try: return path.read_text()
    except FileNotFoundError: return ''

def update(text, key, val):
    section = re.search(r'(?m)^\[bar\][ \t]*(?:#.*)?$', text)
    if not section:
        text = text.rstrip() + '\n\n[bar]\n'
        section = re.search(r'(?m)^\[bar\][ \t]*$', text)
    start = section.end()
    next_section = re.search(r'(?m)^\[[^\]]+\]', text[start:])
    end = start + next_section.start() if next_section else len(text)
    body = text[start:end]
    line = re.compile(r'(?m)^\s*' + re.escape(key) + r'\s*=.*(?:\n|$)')
    body = line.sub('', body)
    if val is not None: body = key + ' = ' + val + '\n' + body.lstrip('\n')
    return text[:start] + '\n' + body.strip('\n') + '\n\n' + text[end:]

args = sys.argv[1:]
if args == ['status']:
    mode = json.loads(shell.read_text()).get('bar', {}).get('background', 'opaque')
    text = read()
    bar = tomllib.loads(text).get('bar', {}) if text.strip() else {}
    alpha = round(float(bar.get('background-alpha', 1)) * 100) if mode != 'none' else 0
    if mode == 'glassy': alpha = min(alpha, 35)
    selected = next((k for k,v in colors.items() if v is not None and v.lower() == str(bar.get('text','')).lower()), 'theme')
    print(json.dumps({'opacity': alpha, 'color': selected}))
elif len(args) == 2 and args[0] == 'opacity' and args[1].isdigit() and int(args[1]) in range(0, 101, 5):
    value = int(args[1])
    atomic(path, update(read(), 'background-alpha', f'{value / 100:.2f}'))
    atomic(hypr, '-- Blue View bar background blur.\n' + ('hl.layer_rule({ match = { namespace = "^omarchy-bar$" }, blur = true, ignore_alpha = 0.01 })\n' if 0 < value < 100 else ''))
    subprocess.run(['omarchy', 'bar', 'background', 'none' if value == 0 else 'opaque'], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['hyprctl', 'reload'], check=True, stdout=subprocess.DEVNULL)
    errors = subprocess.check_output(['hyprctl', 'configerrors'], text=True).strip()
    if errors: raise RuntimeError(errors)
elif len(args) == 2 and args[0] == 'color' and args[1] in colors:
    value = colors[args[1]]
    atomic(path, update(read(), 'text', json.dumps(value) if value else None))
else:
    raise SystemExit('Invalid bar setting')
