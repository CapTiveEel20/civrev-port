<#
.SYNOPSIS
  Tests for tools\make_kit.ps1 (plain PowerShell 5.1). Needs a clean git tree.
  Exit 0 = all pass.
#>
$ErrorActionPreference = "Stop"
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$makeKit = Join-Path $repo "tools\make_kit.ps1"
$script:failed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "PASS $Msg" } else { Write-Host "FAIL $Msg" -ForegroundColor Red; $script:failed++ }
}
function Invoke-MakeKit([string[]]$KitArgs) {
    $ErrorActionPreference = "Continue"
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $makeKit @KitArgs 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Out = $out }
}

# Personal data that must never ship: the Windows user folder of whoever runs this
# test, and e-mail addresses of common providers (no names written here).
$userName = [regex]::Escape($env:USERNAME)
$leakPattern = "\\Users\\$userName\b|/Users/$userName\b|[A-Za-z0-9._%+-]+@(gmail|outlook|hotmail|live|yahoo|icloud)\.com"

$expected = @(
    "Setup.bat", "README-PLAYERS.txt",
    "civrev-port/CMakeLists.txt", "civrev-port/build.ps1", "civrev-port/LICENSE",
    "civrev-port/src/port/civrev_hle.cpp",
    "civrev-port/src/compat/dirent.h", "civrev-port/src/compat/unistd.h", "civrev-port/src/compat/LICENSE-tornado",
    "civrev-port/tools/relift.ps1", "civrev-port/tools/fix_import_stub_toc.py", "civrev-port/tools/fix_inline_opd_funcs.py",
    "civrev-port/launcher/CivRev.c", "civrev-port/launcher/CivRev.rc", "civrev-port/launcher/build_launcher.ps1",
    "civrev-port/setup/setup.ps1", "civrev-port/setup/kitlib.ps1", "civrev-port/setup/ps3recomp.lock"
) | ForEach-Object { "CivRevPC/$_" } | Sort-Object

# ---- refuses a dirty tree ----
$dirty = Join-Path $repo "kit_dirty_test.tmp"
Set-Content -LiteralPath $dirty "x"
try {
    $r = Invoke-MakeKit @("-Version", "dirtytest")
    Assert ($r.Code -eq 1) "dirty tree -> exit 1 (got $($r.Code))"
    Assert ($r.Out -match "commit your changes first") "dirty tree -> 'commit your changes first'"
    Assert (-not (Test-Path (Join-Path $repo "dist\CivRevPC-dirtytest.zip"))) "dirty tree -> no zip"
} finally { Remove-Item -LiteralPath $dirty -Force }

# ---- clean tree -> exact allowlist ----
$zip = Join-Path $repo "dist\CivRevPC-test.zip"
Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
$r = Invoke-MakeKit @("-Version", "test")
Assert ($r.Code -eq 0) "clean tree -> exit 0 (got $($r.Code)) $($r.Out)"
Assert (Test-Path -LiteralPath $zip) "clean tree -> dist\CivRevPC-test.zip exists"
if (Test-Path -LiteralPath $zip) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $names = @($z.Entries | Where-Object { -not $_.FullName.EndsWith("/") } | ForEach-Object { $_.FullName } | Sort-Object)
        $extra = @($names | Where-Object { $_ -notin $expected })
        $miss = @($expected | Where-Object { $_ -notin $names })
        Assert ($extra.Count -eq 0) "zip has no files outside the allowlist (extra: $($extra -join ', '))"
        Assert ($miss.Count -eq 0) "zip has every allowlisted file (missing: $($miss -join ', '))"
        $leaks = @()
        $readme = ""
        foreach ($e in $z.Entries) {
            if ($e.FullName.EndsWith("/")) { continue }
            $sr = New-Object IO.StreamReader($e.Open())
            $text = $sr.ReadToEnd(); $sr.Dispose()
            if ($text -match $leakPattern) { $leaks += $e.FullName }
            if ($e.FullName -eq "CivRevPC/README-PLAYERS.txt") { $readme = $text }
            if ($e.FullName -eq "CivRevPC/Setup.bat") { $bat = $text }
        }
        Assert ($leaks.Count -eq 0) "no personal paths or email in any file (found in: $($leaks -join ', '))"
        Assert ($readme -match "F9" -and $readme -match "F11" -and $readme -match "auto_capture") "README-PLAYERS documents F9, F11, auto_capture"
        Assert ($bat -match "`r`n") "Setup.bat has Windows line endings"
    } finally { $z.Dispose() }
    Remove-Item -LiteralPath $zip -Force
}
if ($script:failed) { Write-Host "$script:failed FAILED" -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS"
exit 0
