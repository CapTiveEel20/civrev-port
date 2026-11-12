<#
.SYNOPSIS
  Build and run the launcher settings test (settings_test.c includes ../CivRev.c).
  Exit code 0 = all pass.
#>
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Llvm.Clang -property installationPath
if (-not $vsPath) { throw "No Visual Studio with 'C++ Clang Compiler for Windows' found." }
$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
cmd /c "`"$vcvars`" >nul 2>nul && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2]) }
}
$out = Join-Path $env:TEMP "civrev_settings_test"
New-Item -ItemType Directory -Force -Path $out | Out-Null
clang-cl /nologo /W4 -Wno-missing-field-initializers settings_test.c "/Fo$out\" "/Fe$out\settings_test.exe" /link user32.lib
if ($LASTEXITCODE -ne 0) { Write-Host "BUILD FAILED"; exit 1 }
& "$out\settings_test.exe"
exit $LASTEXITCODE
