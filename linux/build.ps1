# Packages Oranix Player for Linux -> linux\out\oranix-player-linux.tar.gz
# (the same mpv config as Windows + install.sh; runs on any CPU mpv runs on: x86_64, ARM64, ...)
$ErrorActionPreference = 'Stop'
$src = Split-Path $PSScriptRoot
$out = "$PSScriptRoot\out"
$pkg = "$out\oranix-player"
Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $pkg | Out-Null
robocopy "$src\player\config" "$pkg\config" /E /NFL /NDL /NJH /NJS | Out-Null
Copy-Item "$PSScriptRoot\install.sh", "$PSScriptRoot\uninstall.sh" $pkg
Copy-Item "$src\docs\oranix-player-icon.png" "$pkg\oranix-player.png"
# Shell scripts must have Unix line endings to run.
foreach ($f in 'install.sh', 'uninstall.sh') {
  $t = [IO.File]::ReadAllText("$pkg\$f") -replace "`r`n", "`n"
  [IO.File]::WriteAllText("$pkg\$f", $t, (New-Object Text.UTF8Encoding $false))
}
@"
Oranix Player for Linux
=======================
1. Install mpv (sudo apt install mpv / dnf / pacman / flatpak).
2. In this folder run:   bash install.sh
3. Open "Oranix Player" from your app menu, or:   oranix-player video.mkv
Remove with:  bash uninstall.sh
https://github.com/lazankit/oranix
"@ -replace "`r`n", "`n" | Set-Content "$pkg\README.txt" -NoNewline -Encoding ascii
tar -czf "$out\oranix-player-linux.tar.gz" -C $out oranix-player
"Linux package: $out\oranix-player-linux.tar.gz"
