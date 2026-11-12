<#
.SYNOPSIS
  Pack the player build kit: dist\CivRevPC-<version>.zip.
  Contains ONLY the files needed to build and play (the allowlist below), taken
  from the last commit; refuses to run with uncommitted changes.
  Zip layout: CivRevPC\Setup.bat, CivRevPC\README-PLAYERS.txt, CivRevPC\civrev-port\...

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\make_kit.ps1
  powershell -ExecutionPolicy Bypass -File tools\make_kit.ps1 -Version 1.0
#>
param([string]$Version)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

# Files a player needs (paths in this repo). Everything else stays out.
$Allow = @(
    "CMakeLists.txt", "build.ps1", "LICENSE",
    "src/port/civrev_hle.cpp",
    "src/compat/dirent.h", "src/compat/unistd.h", "src/compat/LICENSE-tornado",
    "tools/relift.ps1", "tools/fix_import_stub_toc.py", "tools/fix_inline_opd_funcs.py",
    "launcher/CivRev.c", "launcher/CivRev.rc", "launcher/build_launcher.ps1",
    "setup/setup.ps1", "setup/kitlib.ps1", "setup/ps3recomp.lock"
)
$Top = @("setup/Setup.bat", "setup/README-PLAYERS.txt")    # go to the kit's top folder

$dirty = git status --porcelain
if ($dirty) {
    Write-Host "The working tree has uncommitted changes: commit your changes first."
    $dirty | ForEach-Object { Write-Host "  $_" }
    exit 1
}
$tracked = @(git ls-files)
foreach ($f in $Allow + $Top) {
    if ($f -notin $tracked) { Write-Host "missing from repo: $f"; exit 1 }
}
if (-not $Version) { $Version = (git describe --always --dirty).Trim() }

$stage = Join-Path $env:TEMP ("civrevpc-kit-" + [guid]::NewGuid().ToString("N"))
$kit = Join-Path $stage "CivRevPC"
try {
    New-Item -ItemType Directory -Force -Path $kit | Out-Null
    # git archive applies .gitattributes (CRLF for .ps1/.bat) and only sees committed files.
    git archive --format=zip --prefix=civrev-port/ -o "$stage\port.zip" HEAD -- @Allow
    if ($LASTEXITCODE -ne 0) { throw "git archive failed" }
    git archive --format=zip -o "$stage\top.zip" HEAD -- @Top
    if ($LASTEXITCODE -ne 0) { throw "git archive failed" }
    Expand-Archive -LiteralPath "$stage\port.zip" -DestinationPath $kit
    Expand-Archive -LiteralPath "$stage\top.zip" -DestinationPath "$stage\top"
    foreach ($f in $Top) { Move-Item -LiteralPath (Join-Path "$stage\top" $f) -Destination $kit }

    New-Item -ItemType Directory -Force -Path (Join-Path $root "dist") | Out-Null
    $zip = Join-Path $root "dist\CivRevPC-$Version.zip"
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($kit, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ("Kit: {0} ({1:N0} KB)" -f $zip, ((Get-Item -LiteralPath $zip).Length / 1KB))
exit 0
