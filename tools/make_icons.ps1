# Tuong duong make_icons.py cho may khong co Python: sinh icon bang System.Drawing.
# Chay tai thu muc goc repo:  powershell -NoProfile -ExecutionPolicy Bypass -File tools/make_icons.ps1
Add-Type -AssemblyName System.Drawing
$root = (Get-Location).Path
New-Item -ItemType Directory -Force "$root\app\Resources" | Out-Null
New-Item -ItemType Directory -Force "$root\repo" | Out-Null
$sizes = [ordered]@{ "AppIcon60x60@2x"=120; "AppIcon60x60@3x"=180; "AppIcon-Small-40@2x"=80;
                     "AppIcon-Small-40@3x"=120; "AppIcon-Small@2x"=58; "AppIcon-Small@3x"=87 }
foreach ($name in $sizes.Keys) {
  $s = [int]$sizes[$name]
  $bmp = New-Object System.Drawing.Bitmap -ArgumentList $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.Clear([System.Drawing.Color]::FromArgb(48, 209, 88))
  $white = [System.Drawing.Brushes]::White
  $y0 = [int][Math]::Floor($s * 0.40); $y1 = [int][Math]::Floor($s * 0.60)
  $x0 = [int][Math]::Floor($s * 0.16); $x1 = [int][Math]::Floor($s * 0.34)
  $g.FillRectangle($white, $x0, $y0, ($x1 - $x0 + 1), ($y1 - $y0 + 1))
  $x0 = [int][Math]::Floor($s * 0.66); $x1 = [int][Math]::Floor($s * 0.84)
  $g.FillRectangle($white, $x0, $y0, ($x1 - $x0 + 1), ($y1 - $y0 + 1))
  $w = [Math]::Max(2, [int][Math]::Floor($s / 28))
  $pen = New-Object System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::White), ([single]$w)
  $g.DrawLine($pen, [int][Math]::Floor($s * 0.36), [int][Math]::Floor($s * 0.50), [int][Math]::Floor($s * 0.64), [int][Math]::Floor($s * 0.50))
  $g.Dispose()
  $bmp.Save("$root\app\Resources\$name.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}
Copy-Item "$root\app\Resources\AppIcon60x60@3x.png" "$root\repo\icon.png" -Force
Write-Output "ok"
