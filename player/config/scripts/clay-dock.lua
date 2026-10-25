-- Clay + glass dock behind uosc's bottom controls: a translucent charcoal sheet with rounded top
-- corners, a soft shadow lifting it off the video, a light top rim, an inner shine and a faint
-- orange glow. It follows uosc's own visibility (user-data/osc/margins) and fades with it.
-- (mpv's OSD can't blur what's behind it, so "glass" here is translucency + highlights.)

local ov = mp.create_osd_overlay("ass-events")
ov.z = -10   -- behind uosc's buttons and timeline

local target, alpha, timer = 0, 0, nil   -- alpha: 0 = hidden .. 1 = fully shown
local bottom = 0                          -- uosc's control area height, as a fraction of the window

local function hex(a) return string.format("%02X", math.floor(255 - a * 255 + 0.5)) end   -- ASS alpha: 00 opaque, FF clear

-- Rounded rect with independent top/bottom radii.
local function shape(x, y, w, h, rt, rb, color, a, extra)
  return string.format(
    "{\\an7\\pos(%d,%d)\\bord0\\shad0%s\\1c&H%s&\\1a&H%s&\\p1}m %d 0 l %d 0 b %d 0 %d 0 %d %d l %d %d b %d %d %d %d %d %d l %d %d b 0 %d 0 %d 0 %d l 0 %d b 0 0 0 0 %d 0{\\p0}",
    x, y, extra or "", color, a,
    rt, w - rt, w, w, w, rt,
    w, h - rb, w, h, w, h, w - rb, h,
    rb, h, h, h, h - rb,
    rt, rt)
end

local function render()
  local w, h = mp.get_osd_size()
  if not w or w == 0 or alpha <= 0.01 or bottom <= 0 then ov:remove() return end
  local s = h / 1080
  local top = math.floor(h * (1 - bottom) - 14 * s)
  local dh = h - top
  local r = math.floor(26 * s)
  local function a(v) return hex(v * alpha) end
  local out = {
    -- soft shadow rising above the sheet
    shape(0, top - math.floor(6 * s), w, dh, r, 0, "000000", a(0.55), string.format("\\blur%d", math.floor(26 * s))),
    -- faint orange ambience under the controls
    shape(math.floor(w * 0.2), top + math.floor(dh * 0.35), math.floor(w * 0.6), math.floor(dh * 0.5), r, r, "007AFF", a(0.10), string.format("\\blur%d", math.floor(40 * s))),
    -- the glass body (smoky, see-through)
    shape(0, top, w, dh, r, 0, "2E2A28", a(0.68)),
    -- clay shine: soft light band across the upper part
    shape(math.floor(r * 0.6), top + math.floor(3 * s), w - math.floor(r * 1.2), math.floor(dh * 0.42), r, math.floor(r * 0.6), "FFFFFF", a(0.05), string.format("\\blur%d", math.floor(8 * s))),
    -- crisp top rim
    shape(math.floor(r * 0.7), top, w - math.floor(r * 1.4), math.max(1, math.floor(1.5 * s)), 1, 1, "FFFFFF", a(0.22)),
  }
  ov.res_x, ov.res_y = w, h
  ov.data = table.concat(out, "\n")
  ov:update()
end

-- Ease towards the target opacity (~140 ms), matching uosc's own fade.
local function animate()
  local step = 0.2
  if math.abs(target - alpha) <= step then alpha = target else alpha = alpha + (target > alpha and step or -step) end
  render()
  if alpha == target and timer then timer:kill(); timer = nil end
end

local function set_target(t)
  target = t
  if not timer then timer = mp.add_periodic_timer(1 / 60 * 2, animate) end
end

-- While the dock shows, lift subtitles above it (sub-margin-y is in 720p-scaled pixels).
local base_sub_margin = mp.get_property_number("sub-margin-y", 22)

mp.observe_property("user-data/osc/margins", "native", function(_, m)
  local b = m and m.b or 0
  if b > 0 then bottom = b end
  set_target(b > 0 and 1 or 0)
  mp.set_property_number("sub-margin-y", b > 0 and math.floor(base_sub_margin + b * 720) or base_sub_margin)
end)
mp.observe_property("osd-dimensions", "native", function() if alpha > 0 then render() end end)
