#!/usr/bin/env python3
"""Exercise the real installer twice against a disposable Omarchy home."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    repo = root / 'source'
    shutil.copytree(source, repo, ignore=shutil.ignore_patterns('.git', '__pycache__'))
    home = root / 'home'
    shell_dir = home / '.config/omarchy'
    hypr = home / '.config/hypr'
    fonts = home / '.local/share/fonts/bvos'
    bindir = root / 'bin'
    for directory in (shell_dir, hypr, fonts, bindir):
        directory.mkdir(parents=True)
    (hypr / 'hyprland.lua').write_text('-- existing user config\n')
    initial = {'plugins': [{'id': 'existing.service'}], 'bar': {'layout': {'right': [{'id': 'existing.widget'}]}}}
    shell = shell_dir / 'shell.json'
    shell.write_text(json.dumps(initial))
    for name in ('Geist-Variable.ttf', 'Manrope-Variable.ttf', 'Inter-Variable.ttf'):
        (fonts / name).write_text('fixture')
    for name in ('omarchy', 'omarchy-toggle', 'hyprctl', 'fc-cache'):
        path = bindir / name
        path.write_text('#!/bin/sh\nexit 0\n')
        path.chmod(0o755)
    for name in ('bvos-hyprbars-build', 'bvos-snap-build'):
        path = repo / 'bin' / name
        path.write_text('#!/bin/sh\nexit 0\n')
        path.chmod(0o755)
    env = dict(os.environ, HOME=str(home), PATH=str(bindir) + ':' + os.environ['PATH'])
    for _ in range(2):
        subprocess.run(['bash', str(repo / 'install.sh'), '--no-theme'], env=env, check=True, stdout=subprocess.DEVNULL)
    result = json.loads(shell.read_text())
    assert [x['id'] for x in result['plugins']] == ['existing.service', 'bvos.screensaver', 'bvos.window-opacity']
    assert [x['id'] for x in result['bar']['layout']['right']] == ['existing.widget', 'bvos-desktop']
    config = (hypr / 'hyprland.lua').read_text()
    assert config.count('require("hypr.bvos-settings")') == 1
    assert (shell_dir / 'plugins/bvos.window-opacity/Service.qml').is_file()
    assert (shell_dir / 'bar/modules/bvos-desktop.qml').is_file()
    assert (home / '.local/bin/bvos-window-opacity').is_file()
print('Installer preserves existing settings and is idempotent.')
