# Blue View OS for Windows 11

The Blue View OS look on Windows 10 and 11, in two parts you can use together or on their own:

1. **[Blue View OS theme](#blue-view-os-theme-windows-11)** (Windows 11): the sky wallpapers, dark mode and Blue View colors, glass windows, a glass taskbar and clean title bars.
2. **[Blue View OS Sky](#blue-view-os-sky-live-wallpaper)** (Windows 10 and 11): the live sky from the Omarchy desktop as your desktop background and screensaver.

## Blue View OS theme (Windows 11)

| Part | What you get | How |
| --- | --- | --- |
| Theme pack | Four 4K wallpapers of the Blue View sky (day, golden hour, dusk, night) changing through the day, dark mode, and the logo's blue (`#38b6ff`) as the accent color | Built into Windows |
| Glass windows | Frosted glass behind app windows and dark title bars | [Mica For Everyone](https://github.com/MicaForEveryone/MicaForEveryone) (free, open source) |
| Glass taskbar | A clear taskbar over the desktop that turns to faint glass when windows are open | [TranslucentTB](https://github.com/TranslucentTB/TranslucentTB) (free, open source) |
| Clean title bars | Title bars without the app icon and title text | [Windhawk](https://windhawk.net) with the "Hide Titlebar Icon and Text" mod (free) |

The installer uses Windows' own `winget` to install the three apps and sets them up for you.

### Install the theme

1. Download **Blue-View-OS-Windows-11-Theme.zip** from [Releases](https://github.com/frank-blueview-ai/Blue-View-Window-Theme-Omarchy/releases) and unzip it.
2. Open the unzipped folder, click the address bar, type `powershell` and press Enter.
3. Run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```

4. Windows asks for permission twice: once to install Windhawk, and once to set up its title bar mod. Say **Yes** to both.

At the end the installer prints a summary of which parts worked. Apps that were already open get the glass the next time you open them.

| Option | What it does |
| --- | --- |
| `-ThemeOnly` | Only the wallpapers, dark mode and colors; no extra apps |
| `-NoGlassWindows`, `-NoGlassTaskbar`, `-NoTitleBars` | Skip a part |
| `-KeepTitleText` | Hide title bar icons but keep window titles |

**Just the wallpapers and colors?** Download **Blue-View-OS.deskthemepack** instead and double-click it.

### Remove the theme

From the same folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

It switches back to the standard Windows dark theme and removes the three apps. Add `-KeepApps` to keep the apps installed, or `-KeepWindhawk` to keep Windhawk for your other mods.

### Limits

- **Title bar buttons stay on the right.** Windows draws minimize, maximize and close itself, and no tool can move them to the left like on Omarchy.
- **Some apps draw their own title bars** (Chrome, Edge, VS Code, Discord, Teams and others), so they don't get glass or clean title bars. The theme leaves these apps alone on purpose, along with File Explorer, where glass has known bugs.
- Windows already snaps windows to edges and corners, and shows tooltips on the title bar buttons.

## Blue View OS Sky (live wallpaper)

The live Blue View OS sky from the Omarchy desktop, as a Windows desktop
background and screensaver. It runs in [Lively Wallpaper](https://www.rocksdanister.com/lively),
a free, open-source wallpaper app for Windows 10 and 11.

- **The sun and moon** sit where they really are in your sky, and the moon shows its real phase.
- **Real stars** come out as it gets dark where you are.
- **Real satellites,** including the ISS, appear when they're truly visible overhead.
- **Clouds** follow your weather (cover, rain, storms, snow, fog) and drift with the real wind.
- **Optional logo, clock and 7-day forecast,** for a screensaver look.

### Install the live sky

1. Install **Lively Wallpaper** from the [Microsoft Store](https://apps.microsoft.com/detail/9ntm2qc6qws7) or [GitHub](https://github.com/rocksdanister/lively/releases).
2. Download **Blue-View-OS-Sky-Lively.zip** from this repo's [Releases](https://github.com/frank-blueview-ai/Blue-View-Window-Theme-Omarchy/releases). Don't unzip it.
3. Open Lively and drag the zip onto its window, or click **+ (Add Wallpaper)** and choose the zip.
4. Click **Blue View OS Sky** in the library to set it as your wallpaper.

### Settings

Right-click **Blue View OS Sky** in Lively's library and choose **Customize**.

| Setting | What it does |
| --- | --- |
| Location | A city, like `Lynn, MA`. Leave it blank to use your internet connection's location. |
| Temperature | Automatic, Fahrenheit or Celsius. |
| Show logo, clock and forecast | Off for a clean desktop, on for a screensaver look. |
| Satellites | On by default. |
| Constellation lines | Off by default. |
| Frame rate | 24 by default. Lower it to save power. |
| Cloud detail | 40% by default. Clouds are soft, so higher values look nearly the same and use more GPU. |

### Screensaver

Lively can run the same sky as your Windows screensaver:

- **Microsoft Store version:** in Lively, open **Settings → Screensaver** and follow the steps. Lively has to keep running in the background.
- **Installer version:** follow Lively's [screensaver guide](https://github.com/rocksdanister/lively/wiki/Screen-Saver).

The screensaver uses your wallpaper's settings, so turn on **Show logo, clock and forecast** if you want the clock on it.

### What's different from Omarchy

- The glass title bars aren't included, because Windows draws its own window buttons.
- Weather comes from [Open-Meteo](https://open-meteo.com). Your location comes from the place you type, or from [GeoJS](https://www.geojs.io) when it's blank.

## Build the packages yourself

On Linux or macOS, with `bash`, `python3`, `curl` and `zip` (plus `chromium` and ImageMagick for the Lively thumbnail):

```bash
windows/build.sh
# -> dist/Blue-View-OS-Sky-Lively.zip
# -> dist/Blue-View-OS-Windows-11-Theme.zip
# -> dist/Blue-View-OS.deskthemepack  (needs the Python "cabarchive" package)
```

The live sky is built from the same sources as the Omarchy screensaver: the astronomy (`Astro.js`), the SGP4 satellite code, the sky shader (`sky.glsl`) and the star catalogue. See `web/`.
