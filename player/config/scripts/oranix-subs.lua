-- Oranix subtitle engine (the menus live in track-popup.lua):
--   * find subtitles online (OpenSubtitles — the same database VLSub uses), by file hash and by name
--   * download one and load it, saved next to the video so it loads automatically next time
--   * sync a subtitle to the audio with alass (bundled on Windows; `alass` on PATH elsewhere)
--   * subtitle style (size, font, background, colour, position), remembered between sessions
-- State for the menus is published as the property user-data/oranix-subs.

local utils = require "mp.utils"

local WIN = package.config:sub(1, 1) == "\\"
local API = "https://rest.opensubtitles.org/search/"
local UA = "TemporaryUserAgent"   -- OpenSubtitles' open user agent for this API

local LANGS = {
  { "eng", "English" }, { "hin", "Hindi" }, { "spa", "Spanish" }, { "fre", "French" }, { "ger", "German" },
  { "ita", "Italian" }, { "por", "Portuguese" }, { "pob", "Portuguese (Brazil)" }, { "rus", "Russian" },
  { "ara", "Arabic" }, { "tur", "Turkish" }, { "jpn", "Japanese" }, { "kor", "Korean" }, { "chi", "Chinese" },
  { "ind", "Indonesian" }, { "tam", "Tamil" }, { "tel", "Telugu" }, { "ben", "Bengali" }, { "urd", "Urdu" },
  { "nep", "Nepali" }, { "dut", "Dutch" }, { "pol", "Polish" }, { "swe", "Swedish" }, { "all", "All languages" },
}

-- ---------- settings (outside the config folder, so saving doesn't trigger a live reload) ----------

local data_dir = WIN and ((os.getenv("LOCALAPPDATA") or os.getenv("TEMP")) .. "\\Oranix\\Player")
  or ((os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")) .. "/oranix-player")
local settings_file = utils.join_path(data_dir, "subtitles.json")
local temp_dir = os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"

local DEFAULTS = { size = 38, font = "Poppins", background = "outline", color = "white", position = 100, lang = "eng" }
local settings = {}

-- Windows tools (cmd, alass) want backslashes; mpv's join_path uses "/".
local function native(p) return WIN and (p:gsub("/", "\\")) or p end

local function mkdir(path)
  path = native(path)
  if WIN then
    mp.command_native({ name = "subprocess", args = { "cmd.exe", "/d", "/c", "mkdir", path }, playback_only = false,
      capture_stdout = true, capture_stderr = true })
  else
    mp.command_native({ name = "subprocess", args = { "mkdir", "-p", path }, playback_only = false })
  end
end

local function load_settings()
  for k, v in pairs(DEFAULTS) do settings[k] = v end
  local f = io.open(settings_file, "r")
  if not f then return end
  local saved = utils.parse_json(f:read("*a") or "")
  f:close()
  if type(saved) == "table" then for k, v in pairs(saved) do if DEFAULTS[k] ~= nil then settings[k] = v end end end
end

local function save_settings()
  local f = io.open(settings_file, "w")
  if not f then mkdir(data_dir); f = io.open(settings_file, "w") end
  if f then f:write(utils.format_json(settings)); f:close() end
end

-- ---------- state for the menus ----------

local state = { status = "idle", results = {}, query = "", lang = "eng" }

local function publish()
  state.lang = settings.lang
  state.settings = settings
  mp.set_property_native("user-data/oranix-subs", state)
end

-- ---------- style ----------

local BACKGROUNDS = {
  outline = { style = "outline-and-shadow", border = 2.6, shadow = 0, back = "#00000000" },
  shadow  = { style = "outline-and-shadow", border = 1.2, shadow = 2.2, back = "#00000000" },
  box     = { style = "background-box", border = 0, shadow = 0, back = "#B3000000" },
}
local COLORS = { white = "#FFFFFF", yellow = "#FFE45C", peach = "#FFD7B3" }

local function apply_style()
  local bg = BACKGROUNDS[settings.background] or BACKGROUNDS.outline
  mp.set_property_number("sub-font-size", settings.size)
  mp.set_property("sub-font", settings.font)
  mp.set_property("sub-color", COLORS[settings.color] or COLORS.white)
  mp.set_property("sub-border-style", bg.style)
  mp.set_property_number("sub-border-size", bg.border)
  mp.set_property_number("sub-shadow-offset", bg.shadow)
  mp.set_property("sub-back-color", bg.back)
  mp.set_property("sub-border-color", "#E6000000")
  mp.set_property_number("sub-pos", settings.position)
  -- Readable fonts are wider; give them a little more line spacing room.
  mp.set_property_number("sub-spacing", (settings.font == "OpenDyslexic" or settings.font == "Lexend") and 0.2 or 0)
end

-- ---------- subprocess helpers ----------

local function run(args, cb, env)
  local cmd = { name = "subprocess", args = args, playback_only = false, capture_stdout = true, capture_stderr = true }
  if env then cmd.env = env end
  mp.command_native_async(cmd, function(ok, res)
    cb(ok and res and res.status == 0, res or {})
  end)
end

local function curl(url, out, cb)
  local args = { WIN and "curl.exe" or "curl", "-s", "-L", "--max-time", "40", "-A", UA, url }
  if out then table.insert(args, "-o"); table.insert(args, out) end
  run(args, cb)
end

local function gunzip(src, dst, cb)
  if WIN then
    local q = function(s) return "'" .. s:gsub("'", "''") .. "'" end
    run({ "powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
      "$i=[IO.File]::OpenRead(" .. q(src) .. "); $o=[IO.File]::Create(" .. q(dst) .. "); " ..
      "$g=New-Object IO.Compression.GZipStream($i,[IO.Compression.CompressionMode]::Decompress); $g.CopyTo($o); $g.Close(); $o.Close(); $i.Close()" }, cb)
  else
    run({ "sh", "-c", 'gzip -dc "$1" > "$2"', "sh", src, dst }, cb)
  end
end

-- ---------- what is playing ----------

-- OpenSubtitles hash: file size + 64-bit sum of the first and last 64 KB (done in two 32-bit halves).
local function os_hash(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  if not size or size < 131072 then f:close() return nil end
  local lo, hi = size % 4294967296, math.floor(size / 4294967296)
  local function add(chunk)
    for i = 1, #chunk - 7, 8 do
      local b1, b2, b3, b4, b5, b6, b7, b8 = chunk:byte(i, i + 7)
      lo = lo + b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
      hi = (hi + b5 + b6 * 256 + b7 * 65536 + b8 * 16777216 + math.floor(lo / 4294967296)) % 4294967296
      lo = lo % 4294967296
    end
  end
  f:seek("set", 0); add(f:read(65536))
  f:seek("set", size - 65536); add(f:read(65536))
  f:close()
  return string.format("%08x%08x", hi, lo), size
end

-- "VisionQuest - S01E03 - Reboot.mkv" -> title "visionquest", season 1, episode 3
local function parse_name(name)
  name = name:gsub("%.[%w]+$", ""):gsub("[%._]", " ")
  local title, s, e = name:match("^(.-)[%s%-%[%(]*[Ss](%d+)%s*[Ee](%d+)")
  if not title then title, s, e = name:match("^(.-)[%s%-]*(%d+)x(%d+)") end
  if not title then
    title = name:match("^(.-)[%s%(%[]+[12][90]%d%d[%)%]%s]") or name:match("^(.-)%s+%d%d%d%dp") or name
  end
  title = title:gsub("%b[]", ""):gsub("%s+%-%s*$", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  return title:lower(), tonumber(s), tonumber(e)
end

local function url_part(s)
  return (s:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function is_local(path) return path and not path:match("^%a[%w+.-]*://") end

-- ---------- search ----------

local function search()
  local path = mp.get_property("path")
  if not path then state.status = "error"; state.message = "Open a video first"; publish() return end
  local name = mp.get_property("filename") or ""
  local title, season, episode = parse_name(is_local(path) and name or (mp.get_property("media-title") or name))
  state.query = title .. (season and string.format("  S%02dE%02d", season, episode) or "")
  state.status, state.results, state.message = "searching", {}, nil
  publish()

  local lang = settings.lang
  local by_name = (episode and ("episode-" .. episode .. "/") or "") .. "query-" .. url_part(title) ..
    (season and ("/season-" .. season) or "") .. "/sublanguageid-" .. lang
  local queries = {}
  local hash, size
  if is_local(path) then hash, size = os_hash(path) end
  if hash then table.insert(queries, { url = API .. "moviebytesize-" .. size .. "/moviehash-" .. hash .. "/sublanguageid-" .. lang, exact = true }) end
  table.insert(queries, { url = API .. by_name })

  -- Release name of the playing file ("visionquest.s01e05.1080p.web.h264-ethel"), to spot subtitles made for it.
  local function release(s) return (s or ""):lower():gsub("%b[]", ""):gsub("%.%w+$", ""):gsub("[%s%._%-]+", ".") end
  local mine = release(name)
  -- Show only what differs between results: drop the title and SxxEyy the header already shows.
  local function short(s)
    local rest = s:match("[Ss]%d+[Ee]%d+[%s%._%-]*(.+)$") or s:match("[12][90]%d%d[%s%._%-%)]*(.+)$")
    return (rest and #rest > 2) and rest or s
  end
  local found, seen, pending, failed = {}, {}, #queries, 0
  local function finish()
    table.sort(found, function(a, b)
      if a.exact ~= b.exact then return a.exact end   -- made for this exact file first
      if a.hi ~= b.hi then return b.hi end            -- then plain over SDH
      return a.downloads > b.downloads
    end)
    state.results = found
    state.status = #found > 0 and "results" or (failed == #queries and "error" or "empty")
    state.message = failed == #queries and "Couldn't reach OpenSubtitles — check your internet" or nil
    publish()
  end
  for _, q in ipairs(queries) do
    curl(q.url, nil, function(ok, res)
      local list = ok and utils.parse_json(res.stdout or "") or nil
      if type(list) ~= "table" then failed = failed + 1 end
      for _, s in ipairs(type(list) == "table" and list or {}) do
        local fmt = (s.SubFormat or ""):lower()
        if not seen[s.IDSubtitleFile] and s.SubDownloadLink and (fmt == "srt" or fmt == "ass" or fmt == "ssa" or fmt == "vtt" or fmt == "sub") then
          seen[s.IDSubtitleFile] = true
          local full = (s.SubFileName or "subtitle"):gsub("%.%w+$", "")
          local same = release(full):gsub("%.hi$", ""):gsub("%.sdh$", "") == mine
            or release(s.MovieReleaseName) == mine
          table.insert(found, {
            name = short(full),
            lang = s.LanguageName or "", iso = s.ISO639 or "", format = fmt,
            downloads = tonumber(s.SubDownloadsCnt) or 0,
            hi = s.SubHearingImpaired == "1", link = s.SubDownloadLink,
            exact = q.exact or s.MatchedBy == "moviehash" or same,
          })
        end
      end
      pending = pending - 1
      if pending == 0 then finish() end
    end)
  end
end

-- ---------- download ----------

local function writable(dir)
  local probe = utils.join_path(dir, ".oranix-write-test")
  local f = io.open(probe, "w")
  if not f then return false end
  f:close(); os.remove(probe)
  return true
end

local function download(index)
  local r = state.results[tonumber(index)]
  if not r then return end
  local path = mp.get_property("path") or ""
  local base = (mp.get_property("filename/no-ext") or "subtitle"):gsub('[<>:"/\\|?*]', "_")
  local dir = is_local(path) and utils.split_path(path) or nil
  if not dir or not writable(dir) then dir = utils.join_path(data_dir, "subtitles"); mkdir(dir) end
  local target = utils.join_path(dir, base .. "." .. (r.iso ~= "" and r.iso or "sub") .. "." .. r.format)
  if utils.file_info(target) then   -- don't overwrite another download for the same video
    target = utils.join_path(dir, base .. "." .. (r.iso ~= "" and r.iso or "sub") .. "." .. os.time() .. "." .. r.format)
  end
  local gz = utils.join_path(temp_dir, "oranix-sub-" .. os.time() .. ".gz")
  mp.osd_message("⤓ Downloading subtitles…", 10)
  curl(r.link, gz, function(ok)
    if not ok then mp.osd_message("Download failed — try another subtitle", 4) return end
    gunzip(gz, target, function(ok2)
      os.remove(gz)
      if not ok2 or not utils.file_info(target) then mp.osd_message("Couldn't unpack the subtitle file", 4) return end
      mp.commandv("sub-add", target, "select", r.lang ~= "" and r.lang or "Downloaded", r.iso)
      mp.osd_message("✓ Subtitles loaded: " .. r.lang .. (r.hi and " (SDH)" or ""), 3)
      state.status = "loaded"; publish()
    end)
  end)
end

-- ---------- sync to audio ----------

local function app_dir()
  local cfg = mp.command_native({ "expand-path", "~~/" })
  return cfg and utils.split_path(cfg:gsub("[\\/]+$", "")) or nil
end

local syncing = false

local function sync()
  if syncing then return end
  local video = mp.get_property("path")
  local sid = mp.get_property_number("sid")
  if not video then mp.osd_message("Open a video first", 3) return end
  local track
  for _, t in ipairs(mp.get_property_native("track-list") or {}) do
    if t.type == "sub" and t.id == sid then track = t end
  end
  if not track then mp.osd_message("Turn on the subtitles you want to sync first", 3) return end
  if track.codec == "hdmv_pgs_subtitle" or track.codec == "dvd_subtitle" or track.codec == "dvb_subtitle" then
    mp.osd_message("Picture-based subtitles can't be synced — try a downloaded one", 4) return
  end

  -- Windows: alass-cli.exe sits next to its ffmpeg.exe/ffprobe.exe, which is where it looks first.
  local exe, ffmpeg = "alass", "ffmpeg"
  if WIN then
    local bin = native(utils.join_path(app_dir() or "", "alass\\bin"))
    exe, ffmpeg = bin .. "\\alass-cli.exe", bin .. "\\ffmpeg.exe"
    if not utils.file_info(exe) then mp.osd_message("Sync isn't installed with this copy of Oranix Player", 4) return end
  end

  local stamp = os.time()
  local out_dir = native(utils.join_path(data_dir, "synced")); mkdir(out_dir)
  local synced = native(utils.join_path(out_dir, (mp.get_property("filename/no-ext") or "sub"):gsub('[<>:"/\\|?*]', "_") .. ".synced." .. stamp .. ".srt"))
  local started = mp.get_time()
  syncing = true
  local tick = mp.add_periodic_timer(1, function()
    mp.osd_message(string.format("⟲ Syncing subtitles to the audio… %d s", mp.get_time() - started), 2)
  end)
  local function done(ok, msg)
    tick:kill(); syncing = false
    mp.osd_message(msg, ok and 3 or 5)
  end

  local function align(sub_path, cleanup)
    run({ exe, video, sub_path, synced }, function(ok, res)
      if cleanup then os.remove(sub_path) end
      if not ok or not utils.file_info(synced) then
        local why = (res.error_string == "init") and (WIN and "Sync engine missing" or "Install alass to sync (alass on your PATH)") or "Couldn't sync these subtitles"
        done(false, "✗ " .. why) return
      end
      local delay = mp.get_property_number("sub-delay", 0)
      mp.commandv("sub-add", synced, "select", (track.title or track.lang or "Subtitles") .. " · synced", track.lang or "")
      if delay ~= 0 then mp.set_property_number("sub-delay", 0) end
      done(true, string.format("✓ Synced to the audio in %d s", mp.get_time() - started))
    end)
  end

  if track.external and track["external-filename"] then
    align(native(track["external-filename"]), false)
  else
    -- Embedded subtitle: copy it out with ffmpeg first.
    local tmp = native(utils.join_path(temp_dir, "oranix-embedded-" .. stamp .. ".srt"))
    run({ ffmpeg, "-y", "-v", "error", "-i", video, "-map", "0:" .. tostring(track["ff-index"]), tmp }, function(ok)
      if not ok then done(false, "✗ Couldn't read the built-in subtitles" .. (WIN and "" or " (needs ffmpeg)")) return end
      align(tmp, true)
    end)
  end
end

-- ---------- messages from the menus ----------

mp.register_script_message("search", function() search() end)
mp.register_script_message("download", download)
mp.register_script_message("sync", sync)
mp.register_script_message("lang", function(code) settings.lang = code; save_settings(); search() end)
mp.register_script_message("style", function(key, value)
  if DEFAULTS[key] == nil or key == "lang" then return end
  settings[key] = tonumber(value) or value
  save_settings(); apply_style(); publish()
end)
mp.register_script_message("reset-style", function()
  for k, v in pairs(DEFAULTS) do if k ~= "lang" then settings[k] = v end end
  save_settings(); apply_style(); publish()
end)

-- Expose the language list to the menu once.
state.languages = {}
for _, l in ipairs(LANGS) do table.insert(state.languages, { code = l[1], name = l[2] }) end

load_settings()
apply_style()
publish()
mp.register_event("file-loaded", function()
  state.status, state.results, state.message = "idle", {}, nil
  publish()
end)
