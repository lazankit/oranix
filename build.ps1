# Builds both Oranix apps into dist\ and (optionally) the installer OranixSetup.exe.
#   .\build.ps1             -> dist\Player, dist\Web
#   .\build.ps1 -Installer  -> also installer\Output\OranixSetup.exe
param([switch]$Installer)
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$dist = Join-Path $src 'dist'
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$common = '/nologo', '/codepage:65001', '/target:winexe', '/platform:x64', '/optimize+'

# Oranix Player: launcher + mpv config
$p = "$dist\Player"
New-Item -ItemType Directory -Force $p | Out-Null
robocopy "$src\player\config" "$p\config" /MIR /NFL /NDL /NJH /NJS | Out-Null
Copy-Item "$src\player\launcher\oranix-player.ico" $p
& $csc @common "/win32icon:$src\player\launcher\oranix-player.ico" "/out:$p\Oranix Player.exe" `
  /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Web.Extensions.dll "$src\player\launcher\OranixPlayer.cs"
if ($LASTEXITCODE) { throw 'Oranix Player build failed' }

# Oranix Web: browser + live files. The WebView2 SDK (Microsoft) is downloaded from NuGet on first build.
if (!(Test-Path "$src\web\sdk\Microsoft.Web.WebView2.Core.dll")) {
  $nupkg = "$env:TEMP\webview2-sdk.zip"
  Invoke-WebRequest 'https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.2903.40' -OutFile $nupkg -UseBasicParsing
  Expand-Archive $nupkg "$env:TEMP\webview2-sdk" -Force
  New-Item -ItemType Directory -Force "$src\web\sdk" | Out-Null
  Copy-Item "$env:TEMP\webview2-sdk\lib\net462\Microsoft.Web.WebView2.Core.dll", "$env:TEMP\webview2-sdk\lib\net462\Microsoft.Web.WebView2.WinForms.dll",
    "$env:TEMP\webview2-sdk\runtimes\win-x64\native\WebView2Loader.dll" "$src\web\sdk"
}
$w = "$dist\Web"
New-Item -ItemType Directory -Force $w | Out-Null
Copy-Item "$src\web\sdk\*", "$src\web\oranix-player.js", "$src\web\start.html", "$src\web\oranix-web.ico" $w
& $csc @common "/win32icon:$src\web\oranix-web.ico" "/out:$w\Oranix Web.exe" `
  "/r:$w\Microsoft.Web.WebView2.Core.dll" "/r:$w\Microsoft.Web.WebView2.WinForms.dll" `
  /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll "$src\web\OranixBrowse.cs"
if ($LASTEXITCODE) { throw 'Oranix Web build failed' }

if ($Installer) {
  & "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" /Q "$src\installer\Oranix.iss"
  if ($LASTEXITCODE) { throw 'Installer build failed' }
  "Installer: $src\installer\Output\OranixSetup.exe"
}
"Built: $dist"
