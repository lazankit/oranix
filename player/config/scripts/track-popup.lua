-- Compact Oranix-style Audio + Subtitles popup (bottom-left), plus a strict
-- subtitle on/off switch.
-- Popup:  hover/scroll/Up/Down to move, click/Enter to pick, Esc or click outside to close.
-- Switch: "toggle-subs" turns subtitles off, or back on with your preferred
--         track (last one you picked, otherwise the best English track).

local ov = mp.create_osd_overlay("ass-events")
local open, items, hover, offset = false, {}, 1, 0
local hide_timer
local MAX_ROWS = 8
local preferred_sub   -- {lang=, title=} of the last subtitle the user picked

local LANGS = { en = "English", eng = "English", hi = "Hindi", hin = "Hindi", es = "Spanish", spa = "Spanish",
  fr = "French", fre = "French", fra = "French", de = "German", ger = "German", deu = "German",
  it = "Italian", ita = "Italian", pt = "Portuguese", por = "Portuguese", ru = "Russian", rus = "Russian",
  ja = "Japanese", jpn = "Japanese", ko = "Korean", kor = "Korean", zh = "Chinese", chi = "Chinese",
  zho = "Chinese", ar = "Arabic", ara = "Arabic", ta = "Tamil", tam = "Tamil", te = "Telugu", tel = "Telugu" }

local function is_english(t)
  local l = (t.lang or ""):lower()
  return l == "en" or l == "eng" or (t.title or ""):lower():find("english", 1, true) ~= nil
end

local function label(t)
  local name = t.lang and (LANGS[t.lang:lower()] or (not t.title and t.lang)) or nil
  if t.title and name and not t.title:lower():find(name:lower(), 1, true) then return name .. " · " .. t.title end
  return t.title or name or ("Track " .. t.id)
end

-- Lower score = better. Plain English first, then English SDH/CC, then forced, then the rest.
local function score(t)
  local title = (t.title or ""):lower()
  local s = is_english(t) and 0 or 10
  if title:find("sdh") or title:find("cc") or t["hearing-impaired"] then s = s + 1 end
  if t.forced or title:find("forced") or title:find("sign") then s = s + 2 end
  return s
end

local function sorted(kind)
  local list = {}
  for _, t in ipairs(mp.get_property_native("track-list") or {}) do
    if t.type == kind then table.insert(list, t) end
  end
  table.sort(list, function(a, b)
    local sa, sb = score(a), score(b)
    if (sa < 10) ~= (sb < 10) then return sa < sb end      -- English group first
    if sa < 10 then return sa == sb and a.id < b.id or sa < sb end
    return label(a):lower() < label(b):lower()             -- others alphabetical
  end)
  return list
end

local mode = "tracks"   -- "tracks" (audio + subtitles) or "speed"
local SPEEDS = { 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2 }

local function build()
  items = {}
  if mode == "speed" then
    local cur = mp.get_property_number("speed", 1)
    table.insert(items, { header = "Playback speed" })
    for _, v in ipairs(SPEEDS) do
      table.insert(items, { kind = "speed", id = v, text = v == 1 and "1× (Normal)" or (v .. "×"),
        active = math.abs(cur - v) < 0.01 })
    end
    return
  end
  local function section(kind, title, with_off)
    local list = sorted(kind)
    if #list == 0 then return end
    table.insert(items, { header = title })
    if with_off then
      local any = false
      for _, t in ipairs(list) do if t.selected then any = true end end
      table.insert(items, { kind = kind, id = "no", text = "Off", active = not any })
    end
    for _, t in ipairs(list) do
      table.insert(items, { kind = kind, id = t.id, text = label(t), active = t.selected, track = t })
    end
  end
  section("audio", "Audio")
  section("sub", "Subtitles", true)
end

-- Geometry in real screen pixels so hit-testing matches the mouse.
local function geo()
  local w, h = mp.get_osd_size()
  local fs = math.floor(h * 0.021)
  local row = math.floor(fs * 1.75)
  local pad = math.floor(fs * 0.6)
  local pw = math.floor(fs * 14)
  local rows = math.min(#items, MAX_ROWS)
  local ph = rows * row + pad * 2
  local x = math.floor(w - pw - h * 0.03)   -- bottom-right, under the buttons that open it
  local y = math.floor(h - h * 0.17 - ph)   -- clear of the uosc control bar + timeline
  return { w = w, h = h, fs = fs, row = row, pad = pad, pw = pw, ph = ph, x = x, y = y, rows = rows }
end

local function rrect(x, y, w, h, r, color, alpha, extra)
  return string.format(
    "{\\an7\\pos(%d,%d)\\bord0\\shad0%s\\1c&H%s&\\1a&H%s&\\p1}m %d 0 l %d 0 b %d 0 %d 0 %d %d l %d %d b %d %d %d %d %d %d l %d %d b 0 %d 0 %d 0 %d l 0 %d b 0 0 0 0 %d 0{\\p0}",
    x, y, extra or "", color, alpha,
    r, w - r, w, w, w, r,
    w, h - r, w, h, w, h, w - r, h,
    r, h, h, h, h - r,
    r, r)
end

local function text(x, y, size, color, bold, s, extra)
  return string.format("{\\an4\\pos(%d,%d)\\fnPoppins\\fs%d\\b%d\\bord0\\shad0\\1c&H%s&%s}%s",
    x, y, size, bold and 1 or 0, color, extra or "", s)
end

local function render()
  if not open then ov:remove() return end
  local g = geo()
  if hover <= offset then offset = hover - 1 end
  if hover > offset + g.rows then offset = hover - g.rows end
  local r = math.floor(g.fs * 1.1)
  -- No \fad here: OSD overlays render at a fixed time, so a fade never completes.
  local fade = ""
  local sh = math.floor(g.fs * 0.15)
  -- Clay + glass: deep soft shadow, smoky translucent body, a lit top rim and a soft inner shine.
  local out = {
    rrect(g.x, g.y + sh * 5, g.pw, g.ph, r, "000000", "50", "\\blur" .. math.floor(g.fs * 1.4) .. fade),                -- lift shadow
    rrect(g.x, g.y, g.pw, g.ph, r, "2E2A28", "4A", fade),                                                               -- glass body
    rrect(g.x + sh, g.y + sh, g.pw - sh * 2, math.floor(g.ph * 0.35), r - sh, "FFFFFF", "F2", "\\blur" .. sh * 4 .. fade), -- clay shine
    rrect(g.x + r, g.y, g.pw - r * 2, math.max(1, math.floor(sh / 2)), 1, "FFFFFF", "C4", fade),                        -- top rim
  }
  for i = 1, g.rows do
    local it = items[i + offset]
    local ry = g.y + g.pad + (i - 1) * g.row
    local cy = ry + g.row / 2
    if it.header then
      table.insert(out, text(g.x + g.fs, cy + g.fs * 0.1, math.floor(g.fs * 0.72), "8C8C8C", true,
        it.header:upper(), "\\fsp2" .. fade))
    else
      if it.active then   -- the chosen row sits on a soft orange clay pill
        table.insert(out, rrect(g.x + g.pad, ry + 2, g.pw - g.pad * 2, g.row - 4, math.floor(r * 0.6), "007AFF", "D6", fade))
      end
      if i + offset == hover then
        table.insert(out, rrect(g.x + g.pad, ry + 2, g.pw - g.pad * 2, g.row - 4, math.floor(r * 0.6), "FFFFFF", "DE", fade))
      end
      if it.active then table.insert(out, text(g.x + g.fs * 0.9, cy, g.fs, "007AFF", true, "✓", fade)) end
      table.insert(out, text(g.x + g.fs * 2.2, cy, g.fs, it.active and "FFFFFF" or "BDBDBD", it.active, it.text, fade))
    end
  end
  if #items > g.rows then   -- slim scrollbar
    local th = g.ph - g.pad * 2
    local bh = math.max(g.row, th * g.rows / #items)
    local by = g.y + g.pad + (th - bh) * offset / (#items - g.rows)
    table.insert(out, rrect(g.x + g.pw - g.pad * 0.7, by, math.max(3, g.fs * 0.18), bh, 2, "007AFF", "00", fade))
  end
  ov.res_x, ov.res_y = g.w, g.h
  ov.data = table.concat(out, "\n")
  ov:update()
end

local close

local function bump()
  if hide_timer then hide_timer:kill() end
  hide_timer = mp.add_timeout(8, function() if open then close() end end)
end

local function move(d)
  local i = hover
  repeat i = i + d until i < 1 or i > #items or not items[i].header
  if i >= 1 and i <= #items then hover = i end
  render(); bump()
end

local function pick(i)
  local it = items[i]
  if not it or it.header then return end
  if it.kind == "speed" then
    mp.set_property_number("speed", it.id)
    mp.osd_message("Speed: " .. it.text)
  else
    mp.set_property(it.kind == "audio" and "aid" or "sid", tostring(it.id))
    if it.kind == "sub" and it.track then preferred_sub = { lang = it.track.lang, title = it.track.title } end
    mp.osd_message((it.kind == "audio" and "Audio: " or "Subtitles: ") .. it.text)
  end
  build(); render(); bump()
end

local function row_at_mouse()
  local m = mp.get_property_native("mouse-pos")
  local g = geo()
  if m.x < g.x or m.x > g.x + g.pw or m.y < g.y or m.y > g.y + g.ph then return nil end
  local i = math.floor((m.y - g.y - g.pad) / g.row) + 1 + offset
  if i >= 1 and i <= #items then return i end
end

local function on_mouse()
  if not open then return end
  local i = row_at_mouse()
  if i and not items[i].header and i ~= hover then hover = i; render() end
  bump()
end

local KEYS = {
  WHEEL_UP = function() move(-1) end, WHEEL_DOWN = function() move(1) end,
  UP = function() move(-1) end, DOWN = function() move(1) end,
  ENTER = function() pick(hover) end, KP_ENTER = function() pick(hover) end,
  ESC = function() close() end,
  MBTN_LEFT = function() local i = row_at_mouse(); if i then pick(i) else close() end end,
  MBTN_LEFT_DBL = function() end,
}

close = function()
  open = false
  for k in pairs(KEYS) do mp.remove_key_binding("track_popup_" .. k) end
  mp.unobserve_property(on_mouse)
  if hide_timer then hide_timer:kill() end
  render()
end

local function show(m)
  if open then close() end
  mode = m
  build()
  open, offset, hover = true, 0, 1
  for i, it in ipairs(items) do if it.active and it.kind ~= "audio" then hover = i end end
  if items[hover] and items[hover].header then move(1) end
  for k, fn in pairs(KEYS) do mp.add_forced_key_binding(k, "track_popup_" .. k, fn, { repeatable = true }) end
  mp.observe_property("mouse-pos", "native", on_mouse)
  render(); bump()
end

-- Strict subtitle switch: off <-> preferred track.
local function toggle_subs()
  local sid = mp.get_property("sid")
  if sid and sid ~= "no" then
    mp.set_property("sid", "no")
    mp.osd_message("Subtitles: Off")
  else
    local subs = sorted("sub")
    if #subs == 0 then mp.osd_message("No subtitles") return end
    local choice = subs[1]
    if preferred_sub then
      for _, t in ipairs(subs) do
        if t.lang == preferred_sub.lang and t.title == preferred_sub.title then choice = t break end
      end
    end
    mp.set_property("sid", tostring(choice.id))
    mp.osd_message("Subtitles: " .. label(choice))
  end
  if open then build(); render() end
end

local function toggle(m) if open and mode == m then close() else show(m) end end
mp.add_key_binding(nil, "toggle", function() toggle("tracks") end)
mp.add_key_binding(nil, "speed", function() toggle("speed") end)
mp.add_key_binding(nil, "toggle-subs", toggle_subs)
mp.observe_property("osd-dimensions", "native", function() if open then render() end end)
mp.register_event("file-loaded", function() if open then build(); render() end end)
