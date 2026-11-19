-- Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
-- Licensed under the PolyForm Noncommercial License 1.0.0.

-- Omarchy's floating workspaces can load a second plugin with the same
-- hyprbars options and button handlers. Skip its availability check only
-- inside the workspace-mode module, where the rest of its layout logic runs.
local workspace_modes = "default.hypr.workspace-modes"
local stock_titlebars = "/usr/lib/omarchy-hyprland-titlebars/titlebars.so"

package.preload[workspace_modes] = function()
  package.preload[workspace_modes] = nil
  local function open(path, ...)
    if path ~= stock_titlebars then
      return io.open(path, ...)
    end
  end

  local env = setmetatable({ io = setmetatable({ open = open }, { __index = io }) }, { __index = _G })
  local path = assert(package.searchpath(workspace_modes, package.path))
  return assert(loadfile(path, "t", env))()
end
