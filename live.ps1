# Live editing: pushes edited files from Oranix-src straight into the installed apps.
# Running apps pick them up instantly - Oranix Web reloads the page, Oranix Player restarts
# the video at the same second. (Only the .cs programs need build.ps1 + a reinstall.)
#   .\live.ps1            -> push player config + web player script + start page
param([string]$InstallDir = "$env:USERPROFILE\Oranix")
$src = $PSScriptRoot
if (!(Test-Path $InstallDir)) { throw "Oranix isn't installed at $InstallDir" }
robocopy "$src\player\config" "$InstallDir\Player\config" /MIR /NFL /NDL /NJH /NJS | Out-Null
foreach ($f in 'oranix-player.js', 'start.html') {
  $from = "$src\web\$f"; $to = "$InstallDir\Web\$f"
  if ((Get-FileHash $from).Hash -ne (Get-FileHash $to -ErrorAction SilentlyContinue).Hash) { Copy-Item $from $to -Force; "updated Web\$f" }
}
"Live update pushed to $InstallDir"
