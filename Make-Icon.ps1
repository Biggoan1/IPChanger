#requires -Version 5.1
<#
.SYNOPSIS
    Generates IPChanger.ico — a multi-resolution app icon for the Network Configuration Tool.
.DESCRIPTION
    Draws a rounded blue-gradient tile with a white hub-and-spoke network motif, renders it
    at all standard sizes (16-256), and packs them into a single .ico (PNG-compressed frames).
    Re-run after tweaking the design; build.ps1 embeds the result into IPChanger.exe.
#>
[CmdletBinding()]
param(
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $OutFile) { $OutFile = Join-Path $root 'IPChanger.ico' }

function New-RoundRectPath {
    param([single]$X, [single]$Y, [single]$W, [single]$H, [single]$R)
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    if ($R -le 0) { $p.AddRectangle((New-Object System.Drawing.RectangleF($X, $Y, $W, $H))); return $p }
    $d = [single]($R * 2)
    $p.AddArc($X,           $Y,           $d, $d, 180, 90)
    $p.AddArc($X + $W - $d, $Y,           $d, $d, 270, 90)
    $p.AddArc($X + $W - $d, $Y + $H - $d, $d, $d,   0, 90)
    $p.AddArc($X,           $Y + $H - $d, $d, $d,  90, 90)
    $p.CloseFigure()
    return $p
}

function New-IconBitmap {
    param([int]$Size)

    $s   = [single]$Size
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    # Rounded-rectangle tile
    $m    = $s * 0.055
    $rect = New-Object System.Drawing.RectangleF($m, $m, ($s - 2*$m), ($s - 2*$m))
    $d    = ($s * 0.20) * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($rect.X,            $rect.Y,             $d, $d, 180, 90)
    $path.AddArc($rect.Right - $d,   $rect.Y,             $d, $d, 270, 90)
    $path.AddArc($rect.Right - $d,   $rect.Bottom - $d,   $d, $d,   0, 90)
    $path.AddArc($rect.X,            $rect.Bottom - $d,   $d, $d,  90, 90)
    $path.CloseFigure()

    $c1    = [System.Drawing.Color]::FromArgb(255,  0, 150, 240)
    $c2    = [System.Drawing.Color]::FromArgb(255,  0,  82, 170)
    $grad  = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 90.0)
    $g.FillPath($grad, $path)

    # --- Gear + plug motif ---
    $cx = $s * 0.5; $cy = $s * 0.5
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

    # Gear cog: flat-topped trapezoidal teeth (4 vertices per tooth, then a valley gap)
    $teeth = 8
    $rTip  = $s * 0.36
    $rBody = $s * 0.285
    $step  = (2 * [Math]::PI) / $teeth
    $fracs = 0.00, 0.12, 0.38, 0.50
    $radii = $rBody, $rTip, $rTip, $rBody
    $cog   = New-Object System.Collections.Generic.List[System.Drawing.PointF]
    for ($i = 0; $i -lt $teeth; $i++) {
        for ($j = 0; $j -lt 4; $j++) {
            $ang = ($i + $fracs[$j]) * $step
            $rr  = [double]$radii[$j]
            $cog.Add((New-Object System.Drawing.PointF([single]($cx + $rr*[Math]::Cos($ang)), [single]($cy + $rr*[Math]::Sin($ang)))))
        }
    }
    $gearPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gearPath.AddPolygon($cog.ToArray())
    $g.FillPath($white, $gearPath)

    # Punch the gear's center hole by re-painting the tile gradient over it
    $rHole = $s * 0.20
    $g.FillEllipse($grad, [single]($cx - $rHole), [single]($cy - $rHole), [single]($rHole*2), [single]($rHole*2))

    # Plug glyph (white) seated in the hole: two prongs, a body, a short cord
    $bodyW = $s * 0.17; $bodyH = $s * 0.10
    $bodyX = $cx - $bodyW/2; $bodyY = $cy - $s*0.03
    $bodyPath = New-RoundRectPath -X $bodyX -Y $bodyY -W $bodyW -H $bodyH -R ($s*0.025)
    $g.FillPath($white, $bodyPath)

    $prongW = $s * 0.034; $prongH = $s * 0.10; $half = $s * 0.045
    foreach ($sx in -1, 1) {
        $px = $cx + $sx*$half - $prongW/2
        $py = $bodyY - $prongH + $s*0.012
        $prong = New-RoundRectPath -X $px -Y $py -W $prongW -H $prongH -R ($prongW/2)
        $g.FillPath($white, $prong)
        $prong.Dispose()
    }

    $cordW = $s * 0.05
    $cordPath = New-RoundRectPath -X ($cx - $cordW/2) -Y ($bodyY + $bodyH - $s*0.005) -W $cordW -H ($s*0.06) -R ($cordW/2)
    $g.FillPath($white, $cordPath)

    $g.Dispose(); $grad.Dispose(); $white.Dispose(); $gearPath.Dispose(); $bodyPath.Dispose(); $cordPath.Dispose(); $path.Dispose()
    return $bmp
}

# Render each size to PNG bytes
$sizes  = 16, 24, 32, 48, 64, 128, 256
$frames = foreach ($sz in $sizes) {
    $bmp = New-IconBitmap -Size $sz
    $ms  = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    [pscustomobject]@{ Size = $sz; Bytes = $ms.ToArray() }
}

# Pack into an .ico container (PNG-compressed frames)
$out = New-Object System.IO.MemoryStream
$bw  = New-Object System.IO.BinaryWriter($out)
$bw.Write([uint16]0)               # reserved
$bw.Write([uint16]1)               # type = icon
$bw.Write([uint16]$frames.Count)
$offset = 6 + 16 * $frames.Count
foreach ($f in $frames) {
    $dim = if ($f.Size -ge 256) { 0 } else { $f.Size }   # 0 means 256 in the ICO spec
    $bw.Write([byte]$dim)          # width
    $bw.Write([byte]$dim)          # height
    $bw.Write([byte]0)             # palette count
    $bw.Write([byte]0)             # reserved
    $bw.Write([uint16]1)           # color planes
    $bw.Write([uint16]32)          # bits per pixel
    $bw.Write([uint32]$f.Bytes.Length)
    $bw.Write([uint32]$offset)
    $offset += $f.Bytes.Length
}
foreach ($f in $frames) { $bw.Write($f.Bytes) }
$bw.Flush()
[System.IO.File]::WriteAllBytes($OutFile, $out.ToArray())
$bw.Dispose(); $out.Dispose()

Write-Host "Wrote $OutFile ($([Math]::Round((Get-Item $OutFile).Length / 1KB, 1)) KB, sizes: $($sizes -join ', '))"
