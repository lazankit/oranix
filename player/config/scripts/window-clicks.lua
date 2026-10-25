-- Double-click like any Windows app: on the title bar = maximize/restore (fills the desktop,
-- taskbar stays); anywhere else on the video = fullscreen.

local TITLE_BAR = 48   -- px at 100% scaling; uosc's top bar is 36 + some slack

mp.add_key_binding(nil, "double-click", function()
  local y = mp.get_property_native("mouse-pos").y
  local scale = mp.get_property_number("display-hidpi-scale", 1)
  if y <= TITLE_BAR * scale and not mp.get_property_bool("fullscreen") then
    mp.commandv("cycle", "window-maximized")
  else
    mp.commandv("cycle", "fullscreen")
  end
end)
