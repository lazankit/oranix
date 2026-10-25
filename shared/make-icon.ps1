# Draws an Oranix app icon as a multi-size .ico, in the brand sheet's two colourways:
#   full (default): orange rounded square + white play mark   -> Oranix Player
#   dark:           charcoal rounded square + orange play mark -> Oranix Web
param([string]$Variant = 'full', [string]$Out = (Join-Path $PSScriptRoot '..\oranix\oranix.ico'))
Add-Type -AssemblyName System.Drawing
$out = $Out
$dark = $Variant -eq 'dark'
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null

function Draw([int]$n) {
  $b = New-Object System.Drawing.Bitmap $n, $n
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.SmoothingMode = 'AntiAlias'
  $r = [single]($n * 0.22); $d = $r * 2; $m = [single]($n * 0.04); $w = $n - 2 * $m
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddArc($m, $m, $d, $d, 180, 90); $path.AddArc($m + $w - $d, $m, $d, $d, 270, 90)
  $path.AddArc($m + $w - $d, $m + $w - $d, $d, $d, 0, 90); $path.AddArc($m, $m + $w - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  $c = { param($hex) [System.Drawing.ColorTranslator]::FromHtml($hex) }
  $bgFrom, $bgTo, $mark, $inner = if ($dark) { '#2E2E2E', '#141414', '#FF7A00', '#FFD7B3' } else { '#FFA94D', '#F25C00', '#FFFFFF', '#FF7A00' }
  $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.PointF 0, 0), (New-Object System.Drawing.PointF $n, $n), (& $c $bgFrom), (& $c $bgTo)
  $g.FillPath($grad, $path)
  if ($dark) { $g.DrawPath((New-Object System.Drawing.Pen ((& $c '#3A3A3A')), ([single][Math]::Max(1, $n / 64))), $path) }
  # Play mark: triangle with rounded joins, slightly right of centre
  $pen = New-Object System.Drawing.Pen (& $c $mark), ([single]($n * 0.09))
  $pen.LineJoin = 'Round'
  $tri = [System.Drawing.PointF[]]@(
    (New-Object System.Drawing.PointF ($n * 0.38), ($n * 0.30)),
    (New-Object System.Drawing.PointF ($n * 0.70), ($n * 0.50)),
    (New-Object System.Drawing.PointF ($n * 0.38), ($n * 0.70)))
  $g.FillPolygon((New-Object System.Drawing.SolidBrush (& $c $mark)), $tri); $g.DrawPolygon($pen, $tri)
  # Inner fold for the brand's two-tone look
  $fold = [System.Drawing.PointF[]]@(
    (New-Object System.Drawing.PointF ($n * 0.42), ($n * 0.40)),
    (New-Object System.Drawing.PointF ($n * 0.58), ($n * 0.50)),
    (New-Object System.Drawing.PointF ($n * 0.42), ($n * 0.60)))
  $g.FillPolygon((New-Object System.Drawing.SolidBrush (& $c $inner)), $fold)
  $ms = New-Object System.IO.MemoryStream
  $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $b.Dispose()
  return ,$ms.ToArray()
}

# ICO container with PNG-compressed entries (supported since Windows Vista).
$sizes = 256, 64, 48, 32, 24, 16
$pngs = $sizes | ForEach-Object { ,(Draw $_) }
$fs = [System.IO.File]::Create($out); $bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $s = $sizes[$i]; $bw.Write([byte]($s % 256)); $bw.Write([byte]($s % 256)); $bw.Write([byte]0); $bw.Write([byte]0)
  $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
  $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Close()
[System.IO.File]::WriteAllBytes([System.IO.Path]::ChangeExtension($out, $null).TrimEnd('.') + '-256.png', $pngs[0])
"icon: $out"
