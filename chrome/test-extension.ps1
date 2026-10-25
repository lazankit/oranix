# Loads the Oranix Chrome extension into a headless Edge, opens a YouTube video and asks the page
# (over the DevTools protocol) whether the Oranix inline skin attached. Also saves a screenshot.
param([string]$Ext, [string]$Shot)
$edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$prof = Join-Path $env:TEMP ('oranix-ext-test-' + [guid]::NewGuid())
$url = 'https://www.youtube.com/watch?v=aqz-KE-bpKQ'
$p = Start-Process $edge -ArgumentList "--headless=new", "--user-data-dir=`"$prof`"", "--load-extension=`"$Ext`"", "--disable-extensions-except=`"$Ext`"",
  "--remote-debugging-port=9333", "--window-size=1400,900", "--autoplay-policy=no-user-gesture-required", "--mute-audio", $url -PassThru
Start-Sleep 14
try {
  $tabs = Invoke-RestMethod 'http://127.0.0.1:9333/json/list'
  $tab = $tabs | ? { $_.type -eq 'page' -and $_.url -like '*youtube*' } | select -First 1
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ws.ConnectAsync([Uri]$tab.webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
  $id = 0
  function Cdp($method, $params) {
    $script:id++
    $msg = @{ id = $script:id; method = $method; params = $params } | ConvertTo-Json -Depth 5 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($msg)
    $ws.SendAsync([ArraySegment[byte]]$bytes, 'Text', $true, [Threading.CancellationToken]::None).Wait()
    $buf = New-Object byte[] 8000000
    while ($true) {
      $sb = New-Object Text.StringBuilder
      do {
        $r = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), [Threading.CancellationToken]::None).Result
        [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $r.Count))
      } until ($r.EndOfMessage)
      $o = $sb.ToString() | ConvertFrom-Json
      if ($o.id -eq $script:id) { return $o.result }
    }
  }
  $res = Cdp 'Runtime.evaluate' @{ expression = "JSON.stringify({ skin: document.documentElement.classList.contains('oranix-skin'), oranix: !!window.__oranix, video: !!document.querySelector('video'), bar: !!document.querySelector('oranix-player') })"; returnByValue = $true }
  "page check: " + $res.result.value
  [void](Cdp 'Input.dispatchMouseEvent' @{ type = 'mouseMoved'; x = 400; y = 300 })
  Start-Sleep -Milliseconds 500
  $img = Cdp 'Page.captureScreenshot' @{ format = 'png' }
  [IO.File]::WriteAllBytes($Shot, [Convert]::FromBase64String($img.data))
  "screenshot saved"
} finally {
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  Get-CimInstance Win32_Process -Filter "name='msedge.exe'" | ? { $_.CommandLine -like "*$prof*" } | % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep 1; Remove-Item $prof -Recurse -Force -ErrorAction SilentlyContinue
}
