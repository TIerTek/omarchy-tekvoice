-- TekVoice keybindings.
--
-- Append this whole block to ~/.config/hypr/bindings.lua, then reload with
--   omarchy restart hyprland
--
-- It is a snippet rather than a standalone file on purpose: Omarchy loads
-- exactly one user bindings file (`require("hypr.bindings")`), after its own
-- defaults. Dropping a new .lua into ~/.config/hypr/ does nothing unless you
-- also require it from hyprland.lua.
--
-- The BEGIN/END markers exist so this block can be found and removed again.

-- BEGIN tiertek.tekvoice
local tekvoice = os.getenv("HOME") .. "/.config/omarchy/plugins/tiertek.tekvoice/bin/tekvoice"

-- The panel needs the shell, because the panel *is* the shell.
o.bind("SUPER + ALT + V", "Open TekVoice", "qs -p /usr/share/omarchy/shell ipc call tiertek.tekvoice toggle")

-- Cycling and panic deliberately call the CLI directly instead of the shell.
-- They talk to PipeWire themselves, so they keep working when the bar widget
-- is disabled or the shell is restarting — which is exactly when you are most
-- likely to be reaching for panic.
o.bind("SUPER + ALT + SHIFT + V", "TekVoice: next voice", tekvoice .. " next")
o.bind("SUPER + ALT + X", "TekVoice: panic (real voice)", tekvoice .. " panic")
-- END tiertek.tekvoice
