<#
.SYNOPSIS
  Build CivRev.exe (the double-clickable launcher) into the civrev-port folder.
  Makes the icon from the game's own ICON0.PNG, then compiles CivRev.c.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File launcher\build_launcher.ps1
  powershell -ExecutionPolicy Bypass -File launcher\build_launcher.ps1 -Crop
  (-Crop = square cut from the middle of the picture instead of the whole
   picture on a transparent square)
#>
param([switch]$Crop)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$port = Split-Path $PSScriptRoot -Parent

# ---- 1. icon: ICON0.PNG -> build\civrev.ico (git-ignored: it is game art) ----
$png = Join-Path $port "..\civrev-gamefiles\vfs\PS3_GAME\ICON0.PNG"
if (-not (Test-Path -LiteralPath $png)) { throw "Game icon not found: $png" }
New-Item -ItemType Directory -Force -Path build | Out-Null
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $png).Path)
$sizes = 256, 128, 64, 48, 32, 24, 16
$frames = New-Object System.Collections.Generic.List[byte[]]
$attr = New-Object System.Drawing.Imaging.ImageAttributes
$attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)   # no faded edges
foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    if ($Crop) {
        $side = $src.Height
        $sx = [int](($src.Width - $side) / 2)
        $dst = New-Object System.Drawing.Rectangle 0, 0, $s, $s
        $g.DrawImage($src, $dst, $sx, 0, $side, $side, [System.Drawing.GraphicsUnit]::Pixel, $attr)
    } else {
        $h = [int][Math]::Round($s * $src.Height / $src.Width)
        $dst = New-Object System.Drawing.Rectangle 0, ([int](($s - $h) / 2)), $s, $h
        $g.DrawImage($src, $dst, 0, 0, $src.Width, $src.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)
    }
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $frames.Add($ms.ToArray())
}
$src.Dispose()

# .ico = 6-byte header + 16-byte entry per image + the PNG images
$ico = Join-Path $PSScriptRoot "build\civrev.ico"
$fs = [System.IO.File]::Create($ico)
$bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $d = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }   # 0 means 256
    $bw.Write([byte]$d); $bw.Write([byte]$d); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$frames[$i].Length); $bw.Write([uint32]$offset)
    $offset += $frames[$i].Length
}
foreach ($f in $frames) { $bw.Write($f) }
$bw.Close()
Write-Host "Icon: $ico ($((Get-Item $ico).Length) bytes)"

# ---- 2. compile, inside the Visual Studio x64 environment (as build.ps1) ----
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found: install Visual Studio 2022 with C++ tools." }
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Llvm.Clang -property installationPath
if (-not $vsPath) { throw "No Visual Studio with 'C++ Clang Compiler for Windows' found." }
$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
cmd /c "`"$vcvars`" >nul 2>nul && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2]) }
}

rc /nologo /fo build\CivRev.res CivRev.rc
if ($LASTEXITCODE -ne 0) { throw "rc failed" }
$out = Join-Path $port "CivRev.exe"
clang-cl /nologo /O2 /MT /W4 -Wno-missing-field-initializers CivRev.c build\CivRev.res /Fobuild\ "/Fe$out" /link /SUBSYSTEM:WINDOWS user32.lib
if ($LASTEXITCODE -ne 0) { throw "compile failed" }
Write-Host "Built: $out"
