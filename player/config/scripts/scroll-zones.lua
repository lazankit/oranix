-- Gestures and levels tuned for a laptop touchpad.
--   Two-finger scroll up/down: left half = brightness, right half = volume.
--   Two-finger scroll sideways: seek 1s per step.
-- Each scroll action fires at most once per 0.1s so touchpads don't race.
-- Keys bind to the same actions (see input.conf) so everything shows one style of bar.

local THROTTLE = 0.1
local SEEK_STEP = 1
local VOL_STEP_WHEEL, VOL_STEP_KEY = 2, 5

-- Brightness is a level from -10 to +10. Darkening leans on gamma so OLED blacks stay
-- black instead of crushing; brightening is gentle so highlights don't blow out.
local level = 0

local function bar(frac)
  local n = math.floor(frac * 20 + 0.5)
  return string.rep("━", n) .. string.rep("┄", 20 - n)
end

local function show(name, frac, value)
  mp.osd_message(string.format("%s   %s   %s", name, bar(math.max(0, math.min(1, frac))), value), 1.2)
end

local function apply_level()
  local gamma = level < 0 and level * 4 or level * 3
  local bright = level < 0 and math.floor(level * 1.5) or level
  mp.set_property_number("gamma", gamma)
  mp.set_property_number("brightness", bright)
  show("Brightness", (level + 10) / 20, string.format("%d%%", 50 + level * 5))
end

local function brightness(d)
  level = math.max(-10, math.min(10, level + d))
  apply_level()
end

local function volume(d)
  local max = mp.get_property_number("volume-max", 200)
  local v = math.max(0, math.min(max, mp.get_property_number("volume", 100) + d))
  mp.set_property_number("volume", v)
  mp.set_property_bool("mute", false)
  show("Volume", v / max, string.format("%d%%", v))
end

local last = 0
local function throttled(fn)
  return function()
    local now = mp.get_time()
    if now - last < THROTTLE then return end
    last = now
    fn()
  end
end

local function left_half()
  local x = mp.get_property_native("mouse-pos").x
  local w = mp.get_property_native("osd-width") or 0
  return x < w / 2
end

local function seek(d)
  mp.commandv("seek", d, "relative+exact")
  mp.commandv("script-binding", "uosc/flash-timeline")
end

mp.add_key_binding(nil, "up",    throttled(function() if left_half() then brightness(1) else volume(VOL_STEP_WHEEL) end end))
mp.add_key_binding(nil, "down",  throttled(function() if left_half() then brightness(-1) else volume(-VOL_STEP_WHEEL) end end))
mp.add_key_binding(nil, "left",  throttled(function() seek(-SEEK_STEP) end))
mp.add_key_binding(nil, "right", throttled(function() seek(SEEK_STEP) end))
mp.add_key_binding(nil, "bright-up",    function() brightness(1) end, { repeatable = true })
mp.add_key_binding(nil, "bright-down",  function() brightness(-1) end, { repeatable = true })
mp.add_key_binding(nil, "bright-reset", function() level = 0; apply_level() end)
mp.add_key_binding(nil, "vol-up",       function() volume(VOL_STEP_KEY) end, { repeatable = true })
mp.add_key_binding(nil, "vol-down",     function() volume(-VOL_STEP_KEY) end, { repeatable = true })
