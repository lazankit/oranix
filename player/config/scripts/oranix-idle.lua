-- Oranix start screen: shown when the player is open with nothing playing.

local ov = mp.create_osd_overlay("ass-events")
local ORANGE, LIGHT, GRAY = "007AFF", "4DA9FF", "B5B5B5"   -- BGR of #FF7A00, #FFA94D, #B5B5B5

local function draw()
  if not mp.get_property_native("idle-active") then ov:remove() return end
  local w, h = mp.get_osd_size()
  if not w or w == 0 then return end
  local s = h / 1080
  local cx, cy = w / 2, h / 2 - 40 * s
  local L = 150 * s                        -- logo size
  local lx, ly = cx - 330 * s, cy - L / 2  -- logo top-left
  local function p(v) return math.floor(v + 0.5) end
  -- Clay tile behind the mark: lift shadow, smoky body, soft shine, lit rim.
  local T = L * 1.6
  local tx, ty, tr = lx + L * 0.45 - T / 2, cy - T / 2, T * 0.26
  local function tile(x, y, w, h, r, color, alpha, extra)
    return string.format("{\\an7\\pos(%d,%d)\\bord0\\shad0%s\\1c&H%s&\\1a&H%s&\\p1}m %d 0 l %d 0 b %d 0 %d 0 %d %d l %d %d b %d %d %d %d %d %d l %d %d b 0 %d 0 %d 0 %d l 0 %d b 0 0 0 0 %d 0{\\p0}",
      p(x), p(y), extra or "", color, alpha, p(r), p(w - r), p(w), p(w), p(w), p(r), p(w), p(h - r), p(w), p(h), p(w), p(h), p(w - r), p(h),
      p(r), p(h), p(h), p(h), p(h - r), p(r), p(r))
  end
  local out = {
    tile(tx, ty + 18 * s, T, T, tr, "000000", "40", "\\blur" .. p(30 * s)),
    tile(tx, ty, T, T, tr, "2E2A28", "20"),
    tile(tx + 6 * s, ty + 6 * s, T - 12 * s, T * 0.4, tr * 0.8, "FFFFFF", "EC", "\\blur" .. p(10 * s)),
    tile(tx + tr, ty, T - tr * 2, 2 * s, 1, "FFFFFF", "B8"),
    -- Soft glow behind the mark
    string.format("{\\an7\\pos(%d,%d)\\bord0\\shad0\\blur%d\\1c&H%s&\\1a&HB0&\\p1}m %d 0 l %d %d l %d %d{\\p0}",
      p(lx), p(ly), p(30 * s), ORANGE, 0, p(L), p(L / 2), 0, p(L)),
    -- Play mark: orange rounded triangle with a light inner fold
    string.format("{\\an7\\pos(%d,%d)\\bord%d\\3c&H%s&\\shad0\\1c&H%s&\\p1}m 0 0 l %d %d l 0 %d{\\p0}",
      p(lx), p(ly), p(14 * s), ORANGE, ORANGE, p(L), p(L / 2), p(L)),
    string.format("{\\an7\\pos(%d,%d)\\bord0\\shad0\\1c&H%s&\\1a&H40&\\p1}m 0 0 l %d %d l 0 %d{\\p0}",
      p(lx + L * 0.18), p(ly + L * 0.3), LIGHT, p(L * 0.4), p(L * 0.2), p(L * 0.4)),
    -- Wordmark
    string.format("{\\an4\\pos(%d,%d)\\fnPoppins\\b1\\fs%d\\bord0\\shad0\\1c&HFFFFFF&}Oran{\\1c&H%s&}ix{\\b0\\fs%d\\fsp%d}  PLAYER",
      p(lx + L + 50 * s), p(cy), p(150 * s), ORANGE, p(38 * s), p(6 * s)),
    -- Tagline + hint
    string.format("{\\an8\\pos(%d,%d)\\fnPoppins\\fs%d\\bord0\\shad0\\1c&H%s&\\fsp%d}Play More. Worry Less.",
      p(cx), p(cy + 120 * s), p(40 * s), GRAY, p(2 * s)),
    string.format("{\\an8\\pos(%d,%d)\\fnPoppins\\fs%d\\bord0\\shad0\\1c&H%s&}Drop a video here  ·  Ctrl+O to open  ·  ? for shortcuts",
      p(cx), p(cy + 200 * s), p(26 * s), "7A7A7A"),
  }
  ov.res_x, ov.res_y = w, h
  ov.data = table.concat(out, "\n")
  ov:update()
end

mp.observe_property("idle-active", "bool", draw)
mp.observe_property("osd-dimensions", "native", draw)
