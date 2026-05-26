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

    # Hub-and-spoke network motif
    $cx = $s * 0.5; $cy = $s * 0.53; $R = $s * 0.24
    $white  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $accent = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 150, 220, 255))
    $pen    = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [single]($s * 0.028))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round

    $pts = foreach ($a in 270, 30, 150) {
        $rad = $a * [Math]::PI / 180
        New-Object System.Drawing.PointF([single]($cx + $R * [Math]::Cos($rad)), [single]($cy + $R * [Math]::Sin($rad)))
    }
    $center = New-Object System.Drawing.PointF([single]$cx, [single]$cy)

    foreach ($p in $pts) { $g.DrawLine($pen, $center, $p) }

    $rN = $s * 0.085; $rC = $s * 0.10
    foreach ($p in $pts) {
        $g.FillEllipse($accent, [single]($p.X - $rN), [single]($p.Y - $rN), [single]($rN*2), [single]($rN*2))
    }
    $g.FillEllipse($white, [single]($cx - $rC), [single]($cy - $rC), [single]($rC*2), [single]($rC*2))

    $g.Dispose(); $grad.Dispose(); $white.Dispose(); $accent.Dispose(); $pen.Dispose(); $path.Dispose()
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
