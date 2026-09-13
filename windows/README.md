# Blue View OS Sky for Windows

The live Blue View OS sky from the Omarchy desktop, as a Windows desktop
background and screensaver. It runs in [Lively Wallpaper](https://www.rocksdanister.com/lively),
a free, open-source wallpaper app for Windows 10 and 11.

- **The sun and moon** sit where they really are in your sky, and the moon shows its real phase.
- **Real stars** come out as it gets dark where you are.
- **Real satellites,** including the ISS, appear when they're truly visible overhead.
- **Clouds** follow your weather (cover, rain, storms, snow, fog) and drift with the real wind.
- **Optional logo, clock and 7-day forecast,** for a screensaver look.

## Install

1. Install **Lively Wallpaper** from the [Microsoft Store](https://apps.microsoft.com/detail/9ntm2qc6qws7) or [GitHub](https://github.com/rocksdanister/lively/releases).
2. Download **Blue-View-OS-Sky-Lively.zip** from this repo's [Releases](https://github.com/frank-blueview-ai/Blue-View-Window-Theme-Omarchy/releases). Don't unzip it.
3. Open Lively and drag the zip onto its window, or click **+ (Add Wallpaper)** and choose the zip.
4. Click **Blue View OS Sky** in the library to set it as your wallpaper.

## Settings

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

## Screensaver

Lively can run the same sky as your Windows screensaver:

- **Microsoft Store version:** in Lively, open **Settings → Screensaver** and follow the steps. Lively has to keep running in the background.
- **Installer version:** follow Lively's [screensaver guide](https://github.com/rocksdanister/lively/wiki/Screen-Saver).

The screensaver uses your wallpaper's settings, so turn on **Show logo, clock and forecast** if you want the clock on it.

## What's different from Omarchy

- The glass title bars aren't included, because Windows draws its own window buttons.
- Weather comes from [Open-Meteo](https://open-meteo.com). Your location comes from the place you type, or from [GeoJS](https://www.geojs.io) when it's blank.

## Build the package yourself

On Linux or macOS, with `bash`, `python3`, `curl` and `zip` (plus `chromium` and ImageMagick for the thumbnail):

```bash
windows/build.sh    # -> dist/Blue-View-OS-Sky-Lively.zip
```

The page is built from the same sources as the Omarchy screensaver: the astronomy (`Astro.js`), the SGP4 satellite code, the sky shader (`sky.glsl`) and the star catalogue. See `web/`.
