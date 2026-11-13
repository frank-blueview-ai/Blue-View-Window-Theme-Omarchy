-- Blue View settings windows and user-selected appearance overrides.
o.window({ class = "^org\\.quickshell$", initial_title = "^Blue View$" }, { float = true, center = true, rounding = 12, opacity = "1 override 1 override" })
o.window({ class = "^org\\.quickshell$", initial_title = "^Window opacity$" }, { float = true, center = true, rounding = 12, opacity = "1 override 1 override" })
require("hypr.bvos-appearance")
require("hypr.bvos-opacity-apps")
require("hypr.bvos-bar-glass")
