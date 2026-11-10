<#
.SYNOPSIS
  Configure (first time) and build civrev.exe with clang-cl + Ninja, inside the
  Visual Studio x64 environment. Extra arguments go to `cmake --build`.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File build.ps1
  powershell -ExecutionPolicy Bypass -File build.ps1 -j 8
#>
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Load the VS x64 developer environment (PATH, INCLUDE, LIB) into this process.
# vswhere ships with every Visual Studio 2017+ install and finds any edition.
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found: install Visual Studio 2022 with C++ tools." }
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Llvm.Clang -property installationPath
if (-not $vsPath) { throw "No Visual Studio with 'C++ Clang Compiler for Windows' found." }
$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
cmd /c "`"$vcvars`" >nul 2>nul && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2]) }
}

if (-not (Test-Path build\build.ninja)) {
    cmake -S . -B build -G Ninja -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
cmake --build build @args
exit $LASTEXITCODE
