# Builds Oranix Web for Android -> android\out\OranixWeb.apk (no Gradle: javac + Android build-tools).
# Needs the JDK and Android SDK in %USERPROFILE%\android-tools (see setup-tools.ps1).
# The player script and start page are shared with the Windows app (..\web).
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$tools = "$env:USERPROFILE\android-tools"
$env:JAVA_HOME = "$tools\jdk"
$env:Path = "$tools\jdk\bin;$env:Path"
$bt = "$tools\sdk\build-tools\34.0.0"
$jar = "$tools\sdk\platforms\android-34\android.jar"
$out = "$src\out"
Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$out\assets", "$out\gen", "$out\classes", "$out\dex" | Out-Null
function Check($what) { if ($LASTEXITCODE) { throw "$what failed" } }

# Launcher icon at every screen density, from the Oranix Web icon.
Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Image]::FromFile("$src\icon.png")
foreach ($d in @{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }.GetEnumerator()) {
  New-Item -ItemType Directory -Force "$out\res\mipmap-$($d.Key)" | Out-Null
  $b = New-Object System.Drawing.Bitmap $d.Value, $d.Value
  $g = [System.Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'
  $g.DrawImage($icon, 0, 0, $d.Value, $d.Value); $g.Dispose()
  $b.Save("$out\res\mipmap-$($d.Key)\ic_launcher.png", [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
}
$icon.Dispose()
Copy-Item "$src\res\*" "$out\res" -Recurse -Force   # adaptive + themed (monochrome) icon, colours
Copy-Item "$src\..\web\oranix-player.js", "$src\..\web\start.html" "$out\assets"

& "$bt\aapt2.exe" compile --dir "$out\res" -o "$out\res.zip"; Check 'aapt2 compile'
& "$bt\aapt2.exe" link -o "$out\base.apk" -I $jar --manifest "$src\AndroidManifest.xml" -A "$out\assets" --java "$out\gen" "$out\res.zip"; Check 'aapt2 link'

$java = Get-ChildItem "$src\src", "$out\gen" -Recurse -Filter *.java | % FullName
& javac -source 8 -target 8 -bootclasspath "$jar;$bt\core-lambda-stubs.jar" -encoding UTF-8 -Xlint:-options -d "$out\classes" @java; Check 'javac'
$classes = Get-ChildItem "$out\classes" -Recurse -Filter *.class | % FullName
& "$bt\d8.bat" --min-api 26 --lib $jar --output "$out\dex" @classes; Check 'd8'

Push-Location "$out\dex"; & jar -uf "$out\base.apk" classes.dex; Pop-Location; Check 'add dex'
& "$bt\zipalign.exe" -f -p 4 "$out\base.apk" "$out\aligned.apk"; Check 'zipalign'

# Signing key: created on first build and never committed (see .gitignore). Keep it - updates must be
# signed with the same key. Set ORANIX_KEYSTORE_PASS to choose its password.
$ks = "$src\oranix-release.jks"
$pass = if ($env:ORANIX_KEYSTORE_PASS) { $env:ORANIX_KEYSTORE_PASS } else { 'oranix-local' }
if (!(Test-Path $ks)) {
  & keytool -genkeypair -keystore $ks -alias oranix -keyalg RSA -keysize 2048 -validity 10000 `
    -storepass $pass -keypass $pass -dname "CN=Oranix, O=Oranix"; Check 'keytool'
}
& "$bt\apksigner.bat" sign --ks $ks --ks-pass "pass:$pass" --out "$out\OranixWeb.apk" "$out\aligned.apk"; Check 'apksigner'
"APK: $out\OranixWeb.apk"
