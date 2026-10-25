# Draws docs/social-preview.png (1280x640), the image GitHub shows when the repo link is shared.
# Upload it in the repo's Settings > General > Social preview.
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot
$fonts = New-Object System.Drawing.Text.PrivateFontCollection
$fonts.AddFontFile("$root\player\config\fonts\Poppins-Bold.ttf")
$fonts.AddFontFile("$root\player\config\fonts\Poppins-Regular.ttf")
$poppins = $fonts.Families[0]
function C($hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }

$W, $H = 1280, 640
$b = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($b)
$g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'
$g.Clear((C '#1F1F1F'))

# Warm orange glow from the top-left, like the start page
$glow = New-Object System.Drawing.Drawing2D.GraphicsPath
$glow.AddEllipse(-300, -420, 1300, 900)
$pg = New-Object System.Drawing.Drawing2D.PathGradientBrush $glow
$pg.CenterColor = [System.Drawing.Color]::FromArgb(110, 255, 122, 0)
$pg.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 31, 31, 31))
$g.FillPath($pg, $glow)

# The two app icons
$p = [System.Drawing.Image]::FromFile("$root\docs\oranix-player-icon.png")
$w = [System.Drawing.Image]::FromFile("$root\docs\oranix-web-icon.png")
$g.DrawImage($p, 96, 150, 150, 150)
$g.DrawImage($w, 266, 150, 150, 150)

# Wordmark: "Oran" white + "ix" orange
$fBig = New-Object System.Drawing.Font $poppins, 92, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$x = 96; $y = 330
$g.DrawString('Oran', $fBig, (New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)), $x, $y)
$oranW = $g.MeasureString('Oran', $fBig, 1000, [System.Drawing.StringFormat]::GenericTypographic).Width
$g.DrawString('ix', $fBig, (New-Object System.Drawing.SolidBrush (C '#FF7A00')), ($x + $oranW + 6), $y)

$fTag = New-Object System.Drawing.Font $poppins, 30, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$g.DrawString('Play More. Worry Less.', $fTag, (New-Object System.Drawing.SolidBrush (C '#D9D9D9')), 100, 460)
$fSub = New-Object System.Drawing.Font $poppins, 22, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$g.DrawString(('Windows  {0}  Linux  {0}  Android  {0}  Chrome  {0}  x64 & ARM  {0}  Open source (MIT)' -f [char]0xB7), $fSub, (New-Object System.Drawing.SolidBrush (C '#9A9A9A')), 100, 515)

# Player screenshot on the right, in a rounded card with a soft shadow
$shot = [System.Drawing.Image]::FromFile("$root\docs\oranix-player.png")
$cx, $cy, $cw = 640, 120, 580
$ch = [int]($cw * $shot.Height / $shot.Width)
function Round($x, $y, $w, $h, $r) {
  $q = New-Object System.Drawing.Drawing2D.GraphicsPath
  $q.AddArc($x, $y, 2 * $r, 2 * $r, 180, 90); $q.AddArc($x + $w - 2 * $r, $y, 2 * $r, 2 * $r, 270, 90)
  $q.AddArc($x + $w - 2 * $r, $y + $h - 2 * $r, 2 * $r, 2 * $r, 0, 90); $q.AddArc($x, $y + $h - 2 * $r, 2 * $r, 2 * $r, 90, 90)
  $q.CloseFigure(); $q
}
for ($i = 12; $i -ge 1; $i--) {
  $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(10, 0, 0, 0))), (Round ($cx - $i) ($cy - $i + 14) ($cw + 2 * $i) ($ch + 2 * $i) 22))
}
$clip = Round $cx $cy $cw $ch 18
$g.SetClip($clip)
$g.DrawImage($shot, $cx, $cy, $cw, $ch)
$g.ResetClip()
$g.DrawPath((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(60, 255, 255, 255)), 1.5), $clip)

$b.Save("$root\docs\social-preview.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $b.Dispose(); $p.Dispose(); $w.Dispose(); $shot.Dispose()
"docs\social-preview.png"
