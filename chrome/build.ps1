# Builds "Oranix for Chrome" (Chrome, Edge, Brave, Vivaldi, Opera... on Windows, macOS, Linux, ChromeOS)
#   -> chrome\out\oranix-chrome\  (load unpacked)  and  chrome\out\oranix-chrome.zip  (store upload)
# The player bar is web\oranix-player.js, shared with Oranix Web. The blocklist comes from the same
# ad-host list the Windows app uses (web\OranixBrowse.cs), so there's one list to maintain.
$ErrorActionPreference = 'Stop'
$src = Split-Path $PSScriptRoot
$out = "$PSScriptRoot\out"
$ext = "$out\oranix-chrome"
Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$ext\icons" | Out-Null
Copy-Item "$PSScriptRoot\manifest.json", "$src\web\oranix-player.js" $ext

# Icons from the Oranix Web icon
Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Image]::FromFile("$src\docs\oranix-web-icon.png")
foreach ($n in 16, 32, 48, 128) {
  $b = New-Object System.Drawing.Bitmap $n, $n
  $g = [System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'
  $g.DrawImage($icon, 0, 0, $n, $n); $g.Dispose()
  $b.Save("$ext\icons\$n.png", [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
}
$icon.Dispose()

# Blocklist -> declarativeNetRequest rules
$cs = [IO.File]::ReadAllText("$src\web\OranixBrowse.cs")
$hostBlock = [regex]::Match($cs, 'AdHosts = new HashSet<string>\([^)]*\)\s*\{(.*?)\};', 'Singleline').Groups[1].Value
$hosts = [regex]::Matches($hostBlock, '"([^"]+)"') | % { $_.Groups[1].Value }
$pathBlock = [regex]::Match($cs, 'AdPaths = \{(.*?)\};', 'Singleline').Groups[1].Value
$paths = [regex]::Matches($pathBlock, '"([^"]+)"') | % { $_.Groups[1].Value }
if ($hosts.Count -lt 20) { throw "Couldn't read the ad-host list from OranixBrowse.cs" }
$rules = @(@{ id = 1; priority = 1; action = @{ type = 'block' }; condition = @{ requestDomains = @($hosts) } })
$id = 2
foreach ($p in $paths) {   # path patterns only for page sub-resources, never whole pages
  $rules += @{ id = $id; priority = 1; action = @{ type = 'block' }
    condition = @{ urlFilter = $p; resourceTypes = @('script', 'image', 'sub_frame', 'xmlhttprequest', 'media', 'ping', 'other') } }
  $id++
}
[IO.File]::WriteAllText("$ext\rules.json", ($rules | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))

# bsdtar writes zip entries with "/" separators (Compress-Archive on PowerShell 5 uses "\", which stores reject).
tar -a -cf "$out\oranix-chrome.zip" -C $ext *
"Chrome extension: $ext  ($($hosts.Count) blocked hosts, $($paths.Count) path rules)"
"Zip: $out\oranix-chrome.zip"
