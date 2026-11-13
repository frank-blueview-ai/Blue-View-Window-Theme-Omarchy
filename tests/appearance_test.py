#!/usr/bin/env python3
"""Exercise settings helpers with a disposable home and simulated Hyprland."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    home = Path(tmp)
    bin_dir = home / 'bin'
    (home / '.config/omarchy').mkdir(parents=True)
    (home / '.config/hypr').mkdir(parents=True)
    bin_dir.mkdir()
    (home / '.config/omarchy/shell.json').write_text('{"bar":{"background":"opaque"}}')
    config = home / '.config/omarchy/shell.toml'
    config.write_text('[font]\nbase-size = 13\n\n[bar]\ntext = "#abcabc"\n\n[tooltip]\ntext = "#fff"\n')
    hypr = bin_dir / 'hyprctl'
    hypr.write_text('''#!/usr/bin/env python3
import json, sys
if sys.argv[1:] == ['-j', 'clients']:
 print(json.dumps([{'address':'0x1234', 'pid':42, 'class':'sample.app'}]))
elif sys.argv[1:] == ['-j', 'getoption', 'decoration:active_opacity']:
 print(json.dumps({'float': 1.0}))
elif sys.argv[1:] == ['configerrors']:
 print('')
else:
 print('ok')
''')
    hypr.chmod(0o755)
    omarchy = bin_dir / 'omarchy'
    omarchy.write_text('#!/bin/sh\nexit 0\n')
    omarchy.chmod(0o755)
    env = dict(os.environ, HOME=str(home), PATH=str(bin_dir) + ':' + os.environ['PATH'])
    bar = source / 'omarchy/plugins/bvos.screensaver/bar-appearance.py'
    opacity = source / 'omarchy/plugins/bvos.window-opacity/control.py'
    def run(script, *args):
        return subprocess.run(['python3', str(script), *args], env=env, check=True, capture_output=True, text=True)
    run(bar, 'opacity', '55')
    run(bar, 'color', 'blue')
    settings = tomllib.loads(config.read_text())
    assert settings['font']['base-size'] == 13 and settings['tooltip']['text'] == '#fff'
    assert settings['bar'] == {'text': '#8edbff', 'background-alpha': .55}
    run(bar, 'color', 'theme')
    assert 'text' not in tomllib.loads(config.read_text())['bar']
    run(opacity, 'set', '0x1234', '42', '75', 'no')
    run(opacity, 'remember', '0x1234', '42', '75', 'yes')
    saved = json.loads((home / '.local/state/bvos/window-opacity.json').read_text())
    assert saved['apps'] == {'sample.app': 75}
    assert 'sample\\\\.app' in (home / '.config/hypr/bvos-opacity-apps.lua').read_text()
    run(opacity, 'reset', '0x1234', '42')
    saved = json.loads((home / '.local/state/bvos/window-opacity.json').read_text())
    assert not saved['apps'] and not saved['windows']
    bad = subprocess.run(['python3', str(opacity), 'set', '0x1234', '99', '75', 'no'], env=env, capture_output=True)
    assert bad.returncode != 0
print('Appearance helpers preserve settings, remember and reset opacity, and reject stale windows.')
