# Blue View OS for macOS

The Blue View OS look on macOS 14 Sonoma and later.

| Part | What you get |
| --- | --- |
| Theme | The Blue View sky wallpaper, dark mode, and Blue View blue accent and highlight colors |
| Live sky desktop | The real sky (sun, moon, stars, satellites, weather and wind-driven clouds) moving behind your windows and desktop icons |
| Screensaver | The sky with the Blue View logo, clock and 7-day forecast |
| Window tiling | **Option + Shift + T** arranges every window on the screen in an even grid; press it again to put them back. Drag a tiled window onto another to swap them. |

The live sky desktop, screensaver and tiling come from **Blue View OS**, a small app in the menu bar (the two ovals). The screensaver is also available as **Blue View Sky** in System Settings.

## Install

In **Terminal**, paste this line and press Return:

```bash
curl -fsSL https://raw.githubusercontent.com/frank-blueview-ai/Blue-View-Window-Theme-Omarchy/main/macos/get.sh | bash
```

Or download **Blue-View-OS-macOS.zip** from [Releases](https://github.com/frank-blueview-ai/Blue-View-Window-Theme-Omarchy/releases), unzip it, and double-click **Install.command** in the "Blue View OS" folder.

macOS asks a few one-time questions:

- **Terminal wants to control System Events:** allow it, to set the wallpaper and dark mode.
- **Accessibility for Blue View OS:** allow it in System Settings → Privacy & Security → Accessibility, for window tiling.

## Use

Click the menu bar icon:

| Menu item | What it does |
| --- | --- |
| Tile All Windows (⌥⇧T) | Tile every window on the screen, or put them back |
| Live Sky Desktop | Turn the moving sky desktop on or off |
| Screensaver | Off, or after 2, 5, 10 or 20 minutes; Show Now |
| Open at Login | Start Blue View OS when you log in |

On macOS 26.4 and later, web pages inside third-party screensavers go blank (an open macOS bug), so the installer turns on the app's own screensaver there instead of selecting Blue View Sky in System Settings.

## Remove

Run `uninstall.sh` (or double-click **Uninstall.command**) in the setup folder: `~/Library/Application Support/BlueViewOS/Setup` if you used the one-line install, otherwise the folder you unzipped. It removes the app and screensaver and restores the default accent colors; dark mode and your wallpaper stay as they are.

## Build

On a Mac with the Xcode command line tools:

```bash
macos/build.sh                                                          # ad-hoc signed, for testing
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" macos/build.sh   # signed for release
```

The GitHub Actions workflow `.github/workflows/macos.yml` builds, signs and notarizes the release zip.
