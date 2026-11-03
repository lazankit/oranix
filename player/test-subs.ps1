# Dev test for the subtitle tools: runs mpv with player\config, drives it over IPC, saves screenshots.
#   .\player\test-subs.ps1 -Video <file> -Out <folder> [-Sync]
param([string]$Video, [string]$Out, [switch]$Sync)
$mpv = 'C:\Program Files\MPV Player\mpv.exe'
$cfg = Join-Path $PSScriptRoot 'config'
$pipe = 'oranix-subtest'
New-Item -ItemType Directory -Force $Out | Out-Null
$p = Start-Process $mpv -ArgumentList "--config-dir=`"$cfg`"", "--input-ipc-server=\\.\pipe\$pipe", '--start=600', '--pause', '--sid=no',
  '--geometry=1600x1000', "`"$Video`"" -PassThru
Start-Sleep 6
function Ipc($cmd) {
  $c = New-Object IO.Pipes.NamedPipeClientStream('.', $pipe, 'InOut'); $c.Connect(4000)
  $w = New-Object IO.StreamWriter($c); $r = New-Object IO.StreamReader($c)
  $w.WriteLine((@{ command = $cmd; request_id = 9 } | ConvertTo-Json -Compress -Depth 5)); $w.Flush()
  do { $l = $r.ReadLine() } until ($l -match '"request_id":9'); $c.Dispose(); ($l | ConvertFrom-Json).data
}
function Shot($name) { [void](Ipc @('screenshot-to-file', (Join-Path $Out "$name.png"), 'window')); Start-Sleep 2 }
try {
  [void](Ipc @('mouse', 600, 400))
  [void](Ipc @('script-binding', 'track_popup/online'))
  for ($i = 0; $i -lt 20; $i++) { Start-Sleep 1; $s = Ipc @('get_property', 'user-data/oranix-subs'); if ($s.status -ne 'searching') { break } }
  "search: status=$($s.status) results=$($s.results.Count) query='$($s.query)'"
  $s.results | Select-Object -First 4 | % { "  $(if ($_.exact) {'[hash] '})$($_.name) | $($_.lang) | $($_.downloads)" }
  Shot 'online'
  [void](Ipc @('script-binding', 'track_popup/online'))   # close menu
  [void](Ipc @('script-message-to', 'oranix_subs', 'download', '1'))
  Start-Sleep 8
  $t = (Ipc @('get_property', 'track-list')) | ? { $_.type -eq 'sub' -and $_.selected }
  "loaded: external=$($t.external) file=$($t.'external-filename')"
  # Move to a line of dialogue so the style is visible.
  for ($i = 0; $i -lt 40; $i++) { [void](Ipc @('seek', '2', 'relative')); Start-Sleep -Milliseconds 400; if (Ipc @('get_property', 'sub-text')) { break } }
  "on screen: '$(Ipc @('get_property', 'sub-text'))'" 
  Shot 'downloaded'
  [void](Ipc @('script-message-to', 'oranix_subs', 'style', 'font', 'OpenDyslexic'))
  [void](Ipc @('script-message-to', 'oranix_subs', 'style', 'size', '48'))
  [void](Ipc @('script-message-to', 'oranix_subs', 'style', 'background', 'box'))
  Start-Sleep 1; "font=$(Ipc @('get_property','sub-font')) size=$(Ipc @('get_property','sub-font-size')) border=$(Ipc @('get_property','sub-border-style'))"; Shot 'styled'
  [void](Ipc @('script-binding', 'track_popup/style')); Start-Sleep 1; Shot 'style-menu'
  [void](Ipc @('script-binding', 'track_popup/style'))
  [void](Ipc @('script-message-to', 'oranix_subs', 'reset-style'))
  if ($Sync) {
    [void](Ipc @('set_property', 'sub-delay', 0))
    $before = Get-Date
    [void](Ipc @('script-message-to', 'oranix_subs', 'sync'))
    for ($i = 0; $i -lt 300; $i++) { Start-Sleep 2; $t = (Ipc @('get_property', 'track-list')) | ? { $_.type -eq 'sub' -and $_.selected }; if ($t.title -like '*synced*') { break } }
    "sync: track='$($t.title)' after $([int]((Get-Date) - $before).TotalSeconds) s"
    Shot 'synced'
  }
  "downloaded file: $($t.'external-filename')"
} finally { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
