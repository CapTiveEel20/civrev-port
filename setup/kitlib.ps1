<#
.SYNOPSIS
  Helper functions for the build kit's Setup (dot-source this file; it only
  defines functions). Tests: setup\tests\kitlib.tests.ps1.
#>

# TITLE_ID from a PS3 PARAM.SFO ("\0PSF" key/value file), or $null.
function Get-SfoTitleId([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $b = [IO.File]::ReadAllBytes($Path)
        if ($b.Length -lt 0x14 -or $b[0] -ne 0 -or $b[1] -ne 0x50 -or $b[2] -ne 0x53 -or $b[3] -ne 0x46) { return $null }
        $keyTab = [BitConverter]::ToUInt32($b, 0x08)
        $dataTab = [BitConverter]::ToUInt32($b, 0x0C)
        $count = [BitConverter]::ToUInt32($b, 0x10)
        for ($i = 0; $i -lt $count; $i++) {
            $e = 0x14 + 16 * $i
            $keyAt = $keyTab + [BitConverter]::ToUInt16($b, $e)
            $end = [Array]::IndexOf($b, [byte]0, [int]$keyAt)
            if ($end -lt 0) { return $null }
            $key = [Text.Encoding]::ASCII.GetString($b, $keyAt, $end - $keyAt)
            if ($key -ne "TITLE_ID") { continue }
            $len = [BitConverter]::ToUInt32($b, $e + 4)
            $at = $dataTab + [BitConverter]::ToUInt32($b, $e + 12)
            return [Text.Encoding]::UTF8.GetString($b, $at, $len).TrimEnd([char]0)
        }
    } catch { }
    return $null
}

# ok | missing | encrypted | not-elf | wrong-version
function Test-EbootFile([string]$Path, [string]$Sha256) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "missing" }
    $fs = [IO.File]::OpenRead($Path)
    try { $head = New-Object byte[] 4; $n = $fs.Read($head, 0, 4) } finally { $fs.Dispose() }
    if ($n -eq 4 -and $head[0] -eq 0x53 -and $head[1] -eq 0x43 -and $head[2] -eq 0x45 -and $head[3] -eq 0) { return "encrypted" }
    if ($n -lt 4 -or $head[0] -ne 0x7F -or $head[1] -ne 0x45 -or $head[2] -ne 0x4C -or $head[3] -ne 0x46) { return "not-elf" }
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($hash -ine $Sha256) { return "wrong-version" }
    return "ok"
}

# Full path of a Python >= 3.10, or $null. The Microsoft Store "python" alias
# (prints nothing useful) and failing commands count as missing.
function Find-Python([string[][]]$Candidates = @(@('py', '-3'), @('python'))) {
    $ErrorActionPreference = "Continue"
    $code = "import sys;print(sys.executable) if sys.version_info>=(3,10) else None"
    foreach ($c in $Candidates) {
        $rest = @(); if ($c.Count -gt 1) { $rest = $c[1..($c.Count - 1)] }
        try { $out = & $c[0] @rest -c $code 2>$null } catch { continue }
        if ($LASTEXITCODE -ne 0 -or -not $out) { continue }
        $exe = ([string]@($out)[-1]).Trim()
        if ($exe -and (Test-Path -LiteralPath $exe -PathType Leaf)) { return $exe }
    }
    return $null
}

$script:VsComponents = @("Microsoft.VisualStudio.Component.VC.Llvm.Clang", "Microsoft.VisualStudio.Component.VC.CMake.Project")

# Install folder of a Visual Studio with C++ Clang + CMake tools, or $null.
function Get-VsInstallPath {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) { return $null }
    $p = & $vswhere -latest -products * -requires $script:VsComponents -property installationPath
    if (-not $p) { return $null }
    return ([string]@($p)[0]).Trim()
}

# Load the VS x64 developer environment (PATH, INCLUDE, LIB) into this process.
function Import-VsDevEnv([string]$VsPath) {
    $vcvars = Join-Path $VsPath "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path -LiteralPath $vcvars)) { throw "vcvars64.bat not found in $VsPath" }
    cmd /c "`"$vcvars`" >nul 2>nul && set" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2]) }
    }
}

function Get-FreeGB([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($full))
    return [Math]::Round($drive.AvailableFreeSpace / 1GB, 1)
}

# The pinned ps3recomp commit (40 lowercase hex characters).
function Read-LockSha([string]$Path) {
    $s = ([string](Get-Content -LiteralPath $Path -Raw)).Trim()
    if ($s -notmatch '^[0-9a-f]{40}$') { throw "Invalid commit id in ${Path}: '$s'" }
    return $s
}

# Same number of files and same total size in both folders.
function Test-TreeCopied([string]$Src, [string]$Dst) {
    if (-not (Test-Path -LiteralPath $Dst -PathType Container)) { return $false }
    $a = @(Get-ChildItem -LiteralPath $Src -Recurse -File -Force) | Measure-Object Length -Sum
    $b = @(Get-ChildItem -LiteralPath $Dst -Recurse -File -Force) | Measure-Object Length -Sum
    return ($a.Count -eq $b.Count -and [long]$a.Sum -eq [long]$b.Sum)
}

# Step markers: <KitRoot>\.setup\<name>.done
function Get-StepMarker([string]$KitRoot, [string]$Name) { Join-Path $KitRoot ".setup\$Name.done" }
function Test-StepDone([string]$KitRoot, [string]$Name) { Test-Path -LiteralPath (Get-StepMarker $KitRoot $Name) }
function Set-StepDone([string]$KitRoot, [string]$Name) {
    $m = Get-StepMarker $KitRoot $Name
    New-Item -ItemType Directory -Force -Path (Split-Path $m) | Out-Null
    Set-Content -LiteralPath $m -Value (Get-Date -Format s)
}
function Clear-StepDone([string]$KitRoot, [string]$Name) {
    Remove-Item -LiteralPath (Get-StepMarker $KitRoot $Name) -Force -ErrorAction SilentlyContinue
}

# Delete what is only needed to rebuild (generated code, compiler output);
# keep build\civrev.exe and build\civrev.map. Returns the bytes freed.
function Remove-BuildLeftovers([string]$PortDir) {
    $targets = @()
    foreach ($d in "src\recomp", "src\spu_gen", "src\gen", "analysis") {
        $p = Join-Path $PortDir $d
        if (Test-Path -LiteralPath $p) { $targets += Get-Item -LiteralPath $p -Force }
    }
    $build = Join-Path $PortDir "build"
    if (Test-Path -LiteralPath $build) {
        $targets += Get-ChildItem -LiteralPath $build -Force | Where-Object { $_.Name -notin "civrev.exe", "civrev.map" }
    }
    [long]$freed = 0
    foreach ($t in $targets) {
        if ($t.PSIsContainer) {
            $s = (@(Get-ChildItem -LiteralPath $t.FullName -Recurse -File -Force) | Measure-Object Length -Sum).Sum
            if ($s) { $freed += [long]$s }
        } else { $freed += $t.Length }
        Remove-Item -LiteralPath $t.FullName -Recurse -Force
    }
    return $freed
}
