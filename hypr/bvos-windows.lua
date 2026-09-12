-- Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
-- Licensed under the PolyForm Noncommercial License 1.0.0.

-- Blue View OS window chrome: slim, near-invisible glass title bars.
-- Minimize, maximize and float dots sit on the left; close is on the far right.
-- The hyprbars plugin is built by `bvos-hyprbars-build` (rebuilt after each
-- `omarchy update` by the post-update hook) and loaded at login.

-- Glass needs blur behind translucent surfaces (Omarchy ships with it off).
hl.config({
  decoration = {
    blur = {
      enabled = true,
      size = 6,
      passes = 2,
      new_optimizations = true,
      ignore_opacity = true,
    },
  },
})

o.exec_on_start("hyprctl plugin load " .. os.getenv("HOME") .. "/.local/lib/bvos/hyprbars.so")

-- Restore minimized windows: SUPER + M shows the tray.
o.bind("SUPER + M", "Show minimized windows", hl.dsp.workspace.toggle_special("minimized"))

local bars = hl.plugin and hl.plugin.hyprbars
if not bars then
  return
end

hl.config({
  plugin = {
    hyprbars = {
      bar_height = 20,
      bar_blur = true,
      -- Barely-there tint over the blurred desktop, so the bar takes on its color.
      bar_color = "rgba(ffffff06)",
      col = { text = "rgba(ffffff59)" },
      bar_title_enabled = true,
      bar_text_size = 9,
      bar_text_font = "Geist, Inter, Sans",
      bar_text_weight = "normal",
      bar_text_align = "center",
      bar_buttons_alignment = "left",
      bar_padding = 10,
      bar_button_padding = 8,
      bar_part_of_window = true,
      bar_precedence_over_border = true,
      icon_on_hover = true,
      inactive_button_color = "rgba(ffffff0d)",
      on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
    },
  },
})

-- Glass dots: a faint hint of color you can see straight through.
local function dot(color, icon, action, align)
  bars.add_button({ bg_color = color, fg_color = "rgba(ffffffb3)", size = 11, icon = icon, action = action, align = align })
end

-- Left, like macOS: minimize, maximize, float.
dot("rgba(febc2e33)", "–", "bvos-window-minimize")
dot("rgba(28c84033)", "+", [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']])
dot("rgba(64b2fc33)", "◇", [[hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })']])

-- Far right: close.
dot("rgba(ff5f5738)", "×", [[hyprctl dispatch 'hl.dsp.window.close()']], "right")
