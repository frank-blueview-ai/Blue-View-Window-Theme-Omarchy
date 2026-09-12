# Blue View OS Desktop

The Blue View OS look for [Omarchy](https://omarchy.org) (Arch Linux + Hyprland):
glass title bars on every window, the **Blue View OS** theme, and a living
above-the-clouds screensaver whose sky follows the real time of day and the
weather outside.

![Screensaver, daytime](screenshots/screensaver-day.jpg)

| Storm at night | Clear night | Snow |
| --- | --- | --- |
| ![Storm](screenshots/screensaver-storm.jpg) | ![Night](screenshots/screensaver-night.jpg) | ![Snow](screenshots/screensaver-snow.jpg) |

## What you get

### Glass title bars
- A slim, 20px bar on every window. It's almost fully transparent over a blur, so it takes on the color of your desktop.
- macOS-style dots on the left for **minimize**, **maximize** and **float**. **Close** sits alone on the far right. Icons only appear when you hover.
- Double-click a title bar to maximize. Minimized windows go to a tray: **SUPER + M** shows it, and the yellow dot restores a window.
- The bars come from [hyprbars](https://github.com/hyprwm/hyprland-plugins/tree/main/hyprbars), with a small patch that lets each button sit on either side. The plugin is built against your installed Hyprland headers, so no `hyprpm` or `sudo` is needed. It rebuilds automatically after `omarchy update`.

### Blue View OS theme
- Brand navy glass, with the logo's blue (`#38b6ff`) and yellow (`#ffde59`) as accents.
- Window borders use a subtle blue-to-yellow gradient.
- Three wallpapers rendered from the screensaver sky: day, golden hour and night.

### Above-the-clouds screensaver
- A GPU-drawn sea of clouds in the style of the [blueview.ai](https://blueview.ai) hero.
- **The sun and moon are the logo's ovals.** The yellow oval crosses the sky between today's real sunrise and sunset, and the blue oval follows the moon.
- **The sky matches the time of day:** dawn and dusk warmth, brand-blue days, and starry navy nights.
- **The clouds follow the weather outside.** The sky clears when it's sunny, turns grey when overcast, and shows rain streaks, storm lightning, drifting snow or fog when those are the real conditions.
- **Golden-ratio composition.** The logo, clock and forecast share one axis at 1/φ across the screen, sit on the golden lines, and scale their type in powers of φ.
- **Current weather and a 7-day forecast** on a clear-glass card that slowly breathes in and out on a 15-second cycle.
- Renders at reduced resolution and 30 fps, so it stays light even on older integrated GPUs.
- Closes on any key or mouse movement, respects idle inhibitors and Omarchy's stay-awake toggle, and never starts over the lock screen. Omarchy still locks at `idle.lock`.

## Requirements

- Omarchy with Hyprland 0.55 or newer (Lua config)
- `jq`, `curl`, `git`, `make`, `g++`, `pkg-config`: all present on a standard Omarchy install
- `qt6-shadertools` (optional): if it's installed, the shader is recompiled locally

## Install

```bash
git clone https://github.com/frank-blueview-ai/Blue-View-Window-Theme-Omarchy.git
cd Blue-View-Window-Theme-Omarchy
./install.sh            # or ./install.sh --no-theme to keep your current theme
```

The script backs up `hyprland.lua` and `shell.json` before editing them.

## Use

| What | How |
| --- | --- |
| Minimize / maximize / float | Left dots on the title bar |
| Close | Right dot on the title bar |
| Show minimized windows | `SUPER + M` |
| Screensaver delay | `idle.screensaver` in `~/.config/omarchy/shell.json` (seconds) |
| Start the screensaver | `omarchy-shell bvos-screensaver show` |
| Preview any weather and hour | `omarchy-shell bvos-screensaver preview <clear\|partly\|cloudy\|overcast\|rain\|storm\|snow\|fog\|live> <0-23\|now>` |
| Demo that ignores input | `omarchy-shell bvos-screensaver demo storm 22`, then `... hide` |
| Rebuild the title-bar plugin | `bvos-hyprbars-build --load` |

Weather uses the location set in Omarchy's weather widget. Current conditions and sun/moon times come from [wttr.in](https://wttr.in); the 7-day forecast comes from [Open-Meteo](https://open-meteo.com).

## Layout of this repo

```
bin/                 bvos-window-minimize, bvos-hyprbars-build
hypr/                bvos-windows.lua (title bars, buttons, blur, SUPER + M)
hyprbars/            per-button alignment patch for hyprbars
hooks/               Omarchy post-update hook that rebuilds the plugin
omarchy/plugins/     bvos.screensaver (Quickshell service, GLSL sky shader, weather)
omarchy/themes/      blue-view-os theme
```

## Uninstall

```bash
./uninstall.sh
```

## License

Copyright (c) 2026 **The Blue View Group Corporation**. Author: **Frank Perez** <frank@blueview.ai>

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE). You may use, modify and share this software for noncommercial purposes. Commercial use requires a separate license from The Blue View Group Corporation; contact frank@blueview.ai.

"Blue View", "Blue View OS" and the Blue View logo are trademarks of The Blue View Group Corporation. The hyprbars patch keeps its upstream BSD 3-Clause license. See [NOTICE](NOTICE) for third-party details.
