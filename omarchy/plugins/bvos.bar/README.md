# Blue View taskbar

An Omarchy bar clone with a fixed padlock before the workspace section. Locked by default, it prevents widget drag-to-move, drag-to-remove, and dragging the entire bar to another edge. Normal clicks, scrolling, and panels still work. The padlock itself cannot be dragged away.

Click the padlock to toggle. State is stored in `bar.layoutLocked` in `~/.config/omarchy/shell.json`. Command-line and Settings layout edits remain available; this is protection against accidental pointer gestures, not an access-control boundary.

```bash
omarchy-shell bvos.bar-layout status
omarchy-shell bvos.bar-layout toggle
```

The installer activates `bvos.bar`, preserves the previous bar choice for uninstall, and restores the workspace widget if it is missing. Reinstalling preserves an explicit unlocked preference and the existing layout.

`Bar.qml` and `BarModel.js` derive from Omarchy commit `fb40ba2dd6a61261703a51449a2253b91ddbc339` and retain its MIT license in `LICENSE.omarchy`. They use the host's `qs.Ui` and `qs.Commons` interfaces. Rebase this clone when those interfaces change; it does not automatically inherit future stock-bar source changes. The lock additions are distributed under the same MIT license.
