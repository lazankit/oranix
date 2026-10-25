# Builds both Oranix apps into dist\ and (optionally) the installer OranixSetup.exe.
#   .\build.ps1             -> dist\Player, dist\Web
#   .\build.ps1 -Installer  -> also installer\Output\OranixSetup.exe
# The apps are AnyCPU .NET Framework programs: they run natively on x64 and on Windows on ARM (ARM64).
param([switch]$Installer)
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$dist = Join-Path $src 'dist'
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$common = '/nologo', '/codepage:65001', '/target:winexe', '/platform:anycpu', '/optimize+'

# Oranix Player: the app + bundled libmpv (x64 and ARM64) + its config (uosc, Oranix scripts, fonts).
# libmpv comes from shinchiro/mpv-winbuild-cmake (pinned build, downloaded on first build).
$mpvBuild = '20261007'; $mpvGit = 'eb0ee10315'
foreach ($a in @(@('x64', 'x86_64'), @('arm64', 'aarch64'))) {
  $dir = "$src\player\libmpv\$($a[0])"
  if (Test-Path "$dir\libmpv-2.dll") { continue }
  New-Item -ItemType Directory -Force $dir | Out-Null
  $archive = "$env:TEMP\mpv-dev-$($a[1]).7z"
  Invoke-WebRequest "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/$mpvBuild/mpv-dev-$($a[1])-$mpvBuild-git-$mpvGit.7z" -OutFile $archive -UseBasicParsing
  tar -xf $archive -C $dir libmpv-2.dll   # Windows' tar reads .7z
}
$p = "$dist\Player"
Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$p\libmpv\x64", "$p\libmpv\arm64" | Out-Null
robocopy "$src\player\config" "$p\config" /MIR /NFL /NDL /NJH /NJS | Out-Null
Copy-Item "$src\player\libmpv\x64\libmpv-2.dll" "$p\libmpv\x64"
Copy-Item "$src\player\libmpv\arm64\libmpv-2.dll" "$p\libmpv\arm64"
Copy-Item "$src\player\launcher\oranix-player.ico", "$src\player\LICENSE.libmpv.GPL" $p
& $csc @common "/win32icon:$src\player\launcher\oranix-player.ico" "/out:$p\Oranix Player.exe" `
  /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Web.Extensions.dll "$src\player\launcher\OranixPlayer.cs"
if ($LASTEXITCODE) { throw 'Oranix Player build failed' }

# Oranix Web: browser + live files. The WebView2 SDK (Microsoft) is downloaded from NuGet on first build,
# with the native loader for both x64 and ARM64.
$sdk = "$src\web\sdk"
if (!(Test-Path "$sdk\runtimes\win-arm64\native\WebView2Loader.dll")) {
  $nupkg = "$env:TEMP\webview2-sdk.zip"
  Invoke-WebRequest 'https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.2903.40' -OutFile $nupkg -UseBasicParsing
  Expand-Archive $nupkg "$env:TEMP\webview2-sdk" -Force
  Remove-Item $sdk -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force "$sdk\runtimes\win-x64\native", "$sdk\runtimes\win-arm64\native" | Out-Null
  Copy-Item "$env:TEMP\webview2-sdk\lib\net462\Microsoft.Web.WebView2.Core.dll", "$env:TEMP\webview2-sdk\lib\net462\Microsoft.Web.WebView2.WinForms.dll" $sdk
  foreach ($arch in 'x64', 'arm64') {
    Copy-Item "$env:TEMP\webview2-sdk\runtimes\win-$arch\native\WebView2Loader.dll" "$sdk\runtimes\win-$arch\native"
  }
}
$w = "$dist\Web"
Remove-Item $w -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $w | Out-Null
Copy-Item "$sdk\*" $w -Recurse
Copy-Item "$src\web\oranix-player.js", "$src\web\start.html", "$src\web\oranix-web.ico" $w
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
