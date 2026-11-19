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
    initial = {'plugins': [{'id': 'existing.service'}], 'bar': {'id': 'existing.bar', 'layout': {'right': [{'id': 'existing.widget'}]}}}
    shell = shell_dir / 'shell.json'
    shell.write_text(json.dumps(initial))
    workspace = shell_dir / 'plugins/custom.workspaces'
    workspace.mkdir(parents=True)
    (workspace / 'manifest.json').write_text(json.dumps({
        'id': 'custom.workspaces', 'omarchy': {'clonedFrom': 'omarchy.workspaces'}}))
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
    subprocess.run(['bash', str(repo / 'install.sh'), '--no-theme'], env=env, check=True, stdout=subprocess.DEVNULL)
    first = json.loads(shell.read_text())
    assert first['bar']['id'] == 'bvos.bar'
    assert first['bar']['layoutLocked'] is True
    assert first['bar']['blueViewPreviousBar'] == 'existing.bar'
    assert first['bar']['layout']['left'] == [{'id': 'custom.workspaces'}]
    # A deliberate unlock and moved workspace must survive reinstalling.
    first['bar']['layoutLocked'] = False
    first['bar']['layout']['center'] = first['bar']['layout'].pop('left')
    shell.write_text(json.dumps(first))
    display = home / '.local/state/bvos/display.json'
    user_shell = shell_dir / 'shell.toml'
    assert json.loads(display.read_text()) == {} and user_shell.exists()
    display.write_text('{"panelTheme":"dark"}\n')
    user_shell.write_text('[font]\nbase-size = 14\n')
    subprocess.run(['bash', str(repo / 'install.sh'), '--no-theme'], env=env, check=True, stdout=subprocess.DEVNULL)
    assert json.loads(display.read_text())['panelTheme'] == 'dark'
    assert user_shell.read_text() == '[font]\nbase-size = 14\n'
    result = json.loads(shell.read_text())
    assert [x['id'] for x in result['plugins']] == ['existing.service', 'bvos.screensaver', 'bvos.window-opacity']
    assert [x['id'] for x in result['bar']['layout']['right']] == ['existing.widget', 'bvos-desktop']
    assert result['bar']['id'] == 'bvos.bar'
    assert result['bar']['layoutLocked'] is False
    assert result['bar']['blueViewPreviousBar'] == 'existing.bar'
    assert result['bar']['layout']['center'] == [{'id': 'custom.workspaces'}]
    assert 'left' not in result['bar']['layout']
    assert (shell_dir / 'plugins/bvos.bar/Bar.qml').is_file()
    assert (shell_dir / 'themes/blue-view-os/shell.toml').is_file()
    config = (hypr / 'hyprland.lua').read_text()
    assert config.count('require("hypr.bvos-settings")') == 1
    assert (shell_dir / 'plugins/bvos.window-opacity/Service.qml').is_file()
    assert (shell_dir / 'bar/modules/bvos-desktop.qml').is_file()
    assert (home / '.local/bin/bvos-window-opacity').is_file()
    subprocess.run(['bash', str(repo / 'uninstall.sh')], env=env, check=True, stdout=subprocess.DEVNULL)
    restored = json.loads(shell.read_text())
    assert restored['bar']['id'] == 'existing.bar'
    assert 'blueViewPreviousBar' not in restored['bar']
    assert restored['bar']['layout']['right'] == [{'id': 'existing.widget'}]
    assert restored['bar']['layout']['center'] == [{'id': 'custom.workspaces'}]
    assert not (shell_dir / 'plugins/bvos.bar').exists()
    assert user_shell.read_text() == '[font]\nbase-size = 14\n'
print('Installer preserves settings, restores workspace numbers, retains unlocks, and restores the previous bar on uninstall.')
