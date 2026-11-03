-- Speed keys and a smarter spacebar.
--   N / M   : speed down / up by 0.25×, from 0.25× to 3.5×
--   Space   : tap = play/pause · hold = 2× while held · double-tap = back to normal speed (1×)

local MIN, MAX, STEP = 0.25, 3.5, 0.25
local HOLD = 0.30         -- seconds before a press counts as a hold
local DOUBLE = 0.35       -- max gap between two taps for a double-tap

local function show_speed()
  local s = mp.get_property_number("speed", 1)
  mp.osd_message(string.format("Speed %s×", (string.format("%.2f", s):gsub("0+$", ""):gsub("%.$", ""))), 1.2)
  mp.commandv("script-binding", "uosc/flash-speed")
end

local function step(dir)
  local s = mp.get_property_number("speed", 1)
  s = math.floor(s / STEP + 0.5) * STEP + dir * STEP     -- snap to the 0.25 grid, then step
  mp.set_property_number("speed", math.max(MIN, math.min(MAX, s)))
  show_speed()
end

mp.add_key_binding(nil, "slower", function() step(-1) end, { repeatable = true })
mp.add_key_binding(nil, "faster", function() step(1) end, { repeatable = true })

-- Spacebar
local hold_timer, boosted, restore_speed = nil, false, 1
local last_tap, last_tap_paused = 0, nil

local function tap()
  local now = mp.get_time()
  if now - last_tap < DOUBLE then
    -- Double-tap: undo the first tap's pause toggle and reset the speed.
    mp.set_property_bool("pause", last_tap_paused)
    mp.set_property_number("speed", 1)
    show_speed()
    last_tap = 0
  else
    last_tap_paused = mp.get_property_bool("pause")
    mp.commandv("cycle", "pause")
    mp.commandv("script-binding", "uosc/flash-timeline")
    last_tap = now
  end
end

local function on_space(e)
  if e.event == "press" then tap() return end   -- one-shot press (no separate key-up), e.g. some remotes
  if e.event == "down" then
    boosted = false
    hold_timer = mp.add_timeout(HOLD, function()
      boosted = true
      restore_speed = mp.get_property_number("speed", 1)
      mp.set_property_number("speed", 2)
      if mp.get_property_bool("pause") then mp.set_property_bool("pause", false) end
      mp.osd_message("▶▶ 2×  (hold)", 30)
    end)
  elseif e.event == "up" then
    if hold_timer then hold_timer:kill(); hold_timer = nil end
    if boosted then
      boosted = false
      mp.set_property_number("speed", restore_speed)
      mp.osd_message("", 0)
      return
    end
    tap()
  end
  -- "repeat" events (key auto-repeat while held) are ignored, so holding never flickers play/pause.
end

mp.add_key_binding(nil, "space", on_space, { complex = true })
