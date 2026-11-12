<#
.SYNOPSIS
  Tests for setup\kitlib.ps1 (plain PowerShell 5.1, no Pester). Exit 0 = all pass.
#>
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\kitlib.ps1")

$script:failed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "PASS $Msg" } else { Write-Host "FAIL $Msg" -ForegroundColor Red; $script:failed++ }
}

# Minimal PARAM.SFO with one UTF-8 entry, TITLE_ID = $Id.
function New-TestSfo([string]$Path, [string]$Id) {
    $key  = [Text.Encoding]::ASCII.GetBytes("TITLE_ID`0")
    $data = New-Object byte[] 16
    [Text.Encoding]::ASCII.GetBytes($Id).CopyTo($data, 0)
    $keyOff = 0x14 + 16
    $dataOff = $keyOff + 12                     # key table padded to 12 bytes
    $ms = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter $ms
    $w.Write([byte[]](0, 0x50, 0x53, 0x46))     # "\0PSF"
    $w.Write([uint32]0x101)                     # version
    $w.Write([uint32]$keyOff); $w.Write([uint32]$dataOff); $w.Write([uint32]1)
    $w.Write([uint16]0); $w.Write([uint16]0x0204)                        # key_off, fmt utf8
    $w.Write([uint32]($Id.Length + 1)); $w.Write([uint32]16); $w.Write([uint32]0)
    $w.Write($key); $w.Write((New-Object byte[] (12 - $key.Length)))
    $w.Write($data); $w.Flush()
    [IO.File]::WriteAllBytes($Path, $ms.ToArray())
}

function New-Bytes([string]$Path, [byte[]]$Head, [int]$Total = 64) {
    $b = New-Object byte[] $Total
    $Head.CopyTo($b, 0)
    [IO.File]::WriteAllBytes($Path, $b)
}

$tmp = Join-Path $env:TEMP ("kitlib-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    # ---- Get-SfoTitleId ----
    New-TestSfo "$tmp\param.sfo" "BLES00238"
    Assert ((Get-SfoTitleId "$tmp\param.sfo") -eq "BLES00238") "Get-SfoTitleId synthetic BLES00238"
    $real = Join-Path $PSScriptRoot "..\..\..\civrev-gamefiles\vfs\PS3_GAME\PARAM.SFO"   # default sibling layout
    if (Test-Path $real) { Assert ((Get-SfoTitleId $real) -eq "BLES00238") "Get-SfoTitleId real disc PARAM.SFO" }
    else { Write-Host "SKIP real PARAM.SFO not present" }
    Set-Content "$tmp\text.sfo" "hello world, not a PSF file at all"
    Assert ($null -eq (Get-SfoTitleId "$tmp\text.sfo")) "Get-SfoTitleId text file -> null"
    Assert ($null -eq (Get-SfoTitleId "$tmp\missing.sfo")) "Get-SfoTitleId missing -> null"

    # ---- Test-EbootFile ----
    $h = "b58d4cf93933cbd921384735f809bc00718550f9fdaf9b75c27ad620e95ee3e0"
    Assert ((Test-EbootFile "$tmp\none.elf" $h) -eq "missing") "Test-EbootFile missing"
    New-Bytes "$tmp\enc.bin" ([byte[]](0x53, 0x43, 0x45, 0))
    Assert ((Test-EbootFile "$tmp\enc.bin" $h) -eq "encrypted") "Test-EbootFile SCE header -> encrypted"
    New-Bytes "$tmp\mz.bin" ([byte[]](0x4D, 0x5A))
    Assert ((Test-EbootFile "$tmp\mz.bin" $h) -eq "not-elf") "Test-EbootFile MZ -> not-elf"
    New-Bytes "$tmp\elf.elf" ([byte[]](0x7F, 0x45, 0x4C, 0x46))
    Assert ((Test-EbootFile "$tmp\elf.elf" $h) -eq "wrong-version") "Test-EbootFile other ELF -> wrong-version"
    $own = (Get-FileHash "$tmp\elf.elf" -Algorithm SHA256).Hash
    Assert ((Test-EbootFile "$tmp\elf.elf" $own) -eq "ok") "Test-EbootFile matching hash -> ok"

    # ---- Find-Python ----
    Assert ($null -eq (Find-Python @(, @('no-such-python-xyz')) @())) "Find-Python unknown command -> null"
    # where.exe fails (exit 2) without interpreting the appended code; 'cmd /c' would treat
    # '>=(3,10)' as a redirection and create a stray file named '(3'.
    Assert ($null -eq (Find-Python @(, @('where.exe', 'no-such-python-xyz')) @())) "Find-Python failing command -> null"
    $py = Find-Python
    Assert ($py -and (Test-Path $py)) "Find-Python default finds an interpreter ($py)"
    # Not on PATH (fresh winget install before a new window): found in the usual install folders.
    $glob = $py -replace 'python\.exe$', 'pytho?.exe'
    $found = Find-Python @(, @('no-such-python-xyz')) @("$tmp\nothing\python.exe", $glob)
    Assert ($found -eq $py) "Find-Python falls back to install-folder globs ($found)"
    Assert ($null -eq (Find-Python @(, @('no-such-python-xyz')) @("$tmp\nothing\python.exe"))) "Find-Python no candidate, no glob match -> null"

    # ---- Get-OutputLineKind / Get-NinjaProgress (what Setup shows on screen) ----
    $kinds = [ordered]@{
        '[59/161] Building C object CMakeFiles\ps3recomp_runtime.dir\libs\audio\cellAudio.c.obj' = "progress"
        '==> 3/5 lift PPU code to C++' = "status"
        'C:\x\ppu_memory.h(310,38): warning: implicit conversion loses integer precision [-Wimplicit-int-conversion]' = "log"
        'C:\x\include\psemu/error_codes.h(12,9): note: expanded from macro ''CELL_EFAULT''' = "log"
        'C:\x\cellKb.h(40,5): note: expanded from macro ''CELL_KB_ERROR_INVALID_PARAMETER''' = "log"
        '        return CELL_KB_ERROR_INVALID_PARAMETER;' = "log"
        'Requirement already satisfied: pyelftools in c:\x\.venv\lib\site-packages' = "log"
        'C:\x\a.c(3,1): error: use of undeclared identifier ''foo''' = "error"
        'clang-cl: error: unknown argument: ''-mfoo''' = "error"
        'LINK : fatal error LNK1104: cannot open file ''x.lib''' = "error"
        'C:\x\a.cpp(1): fatal error C1083: Cannot open include file' = "error"
        'FAILED: CMakeFiles/civrev.dir/src/recomp/ppu_recomp_001.cpp.obj' = "error"
        'ninja: build stopped: subcommand failed.' = "error"
        'CMake Error at CMakeLists.txt:12 (project):' = "error"
        'ERROR: Could not find a version that satisfies the requirement foo' = "error"
        'Traceback (most recent call last):' = "error"
        'ModuleNotFoundError: No module named ''elftools''' = "error"
    }
    foreach ($l in $kinds.Keys) {
        $k = Get-OutputLineKind $l
        Assert ($k -eq $kinds[$l]) "Get-OutputLineKind '$($l.Substring(0, [Math]::Min(50, $l.Length)))' -> $($kinds[$l]) (got $k)"
    }
    $p = Get-NinjaProgress '[59/161] Building C object x.obj'
    Assert ($p[0] -eq 59 -and $p[1] -eq 161) "Get-NinjaProgress [59/161] -> 59, 161"
    Assert ($null -eq (Get-NinjaProgress 'warning: [59/161]')) "Get-NinjaProgress other line -> null"

    # ---- Get-ToolInstallPlan (winget command lines) ----
    Assert (@(Get-ToolInstallPlan $false $false).Count -eq 0) "Get-ToolInstallPlan nothing missing -> empty"
    $plan = @(Get-ToolInstallPlan $true $true)
    Assert ($plan.Count -eq 2) "Get-ToolInstallPlan both missing -> 2 installs"
    $pyArgs = $plan[0].Args -join " "
    Assert ($pyArgs -match '--id Python\.Python\.3\.12' -and $pyArgs -match 'PrependPath=1' -and $pyArgs -match 'InstallAllUsers=0') "Get-ToolInstallPlan Python: id, PATH, per-user"
    $vsArgs = $plan[1].Args
    $ov = $vsArgs[[Array]::IndexOf($vsArgs, "--override") + 1]
    Assert (($vsArgs -join " ") -match '--id Microsoft\.VisualStudio\.2022\.BuildTools') "Get-ToolInstallPlan VS: Build Tools id"
    $hasAll = $true
    foreach ($c in @("Microsoft.VisualStudio.Workload.VCTools") + $script:VsComponents) { if ($ov -notmatch [regex]::Escape("--add $c")) { $hasAll = $false } }
    Assert ($hasAll -and $ov -match '--wait') "Get-ToolInstallPlan VS override adds C++ workload + every component Setup checks for, waits"
    foreach ($e in $plan) { Assert (($e.Args -join " ") -match '--accept-package-agreements' -and $e.Args[0] -eq "install") "Get-ToolInstallPlan '$($e.What)' is a non-interactive install" }
    $only = @(Get-ToolInstallPlan $true $false)
    Assert ($only.Count -eq 1 -and ($only[0].Args -join " ") -match 'BuildTools') "Get-ToolInstallPlan only VS missing -> only VS"

    # ---- Read-LockSha ----
    $sha = "91a6318277151cd8bf541f36ecfd5baedf4ac540"
    Set-Content "$tmp\good.lock" "$sha`r`n"
    Assert ((Read-LockSha "$tmp\good.lock") -eq $sha) "Read-LockSha pinned sha"
    Set-Content "$tmp\bad.lock" "abc"
    $threw = $false; try { Read-LockSha "$tmp\bad.lock" | Out-Null } catch { $threw = $true }
    Assert $threw "Read-LockSha invalid -> throws"

    # ---- Test-TreeCopied ----
    New-Item -ItemType Directory -Force "$tmp\src\sub", "$tmp\dst\sub" | Out-Null
    Set-Content "$tmp\src\a.txt" "aaaa"; Set-Content "$tmp\src\sub\b.txt" "bbbbbbbb"
    Copy-Item "$tmp\src\a.txt" "$tmp\dst\a.txt"; Copy-Item "$tmp\src\sub\b.txt" "$tmp\dst\sub\b.txt"
    Assert (Test-TreeCopied "$tmp\src" "$tmp\dst") "Test-TreeCopied identical -> true"
    Remove-Item "$tmp\dst\sub\b.txt"
    Assert (-not (Test-TreeCopied "$tmp\src" "$tmp\dst")) "Test-TreeCopied file missing -> false"
    Set-Content "$tmp\dst\sub\b.txt" "bb"
    Assert (-not (Test-TreeCopied "$tmp\src" "$tmp\dst")) "Test-TreeCopied truncated -> false"

    # ---- step markers ----
    Assert (-not (Test-StepDone $tmp "lift")) "Test-StepDone initially false"
    Set-StepDone $tmp "lift"
    Assert (Test-StepDone $tmp "lift") "Set-StepDone -> true"
    Clear-StepDone $tmp "lift"
    Assert (-not (Test-StepDone $tmp "lift")) "Clear-StepDone -> false"

    # ---- Remove-BuildLeftovers ----
    $port = "$tmp\port"
    $files = @{ "src\recomp\a.cpp" = 100; "src\gen\b.cpp" = 20; "src\spu_gen\c.c" = 30; "src\port\keep.cpp" = 7;
                "analysis\x.json" = 40; "build\civrev.exe" = 50; "build\civrev.map" = 60;
                "build\CMakeFiles\o.obj" = 70; "build\build.ninja" = 80 }
    foreach ($f in $files.Keys) {
        $p = Join-Path $port $f
        New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
        [IO.File]::WriteAllBytes($p, (New-Object byte[] $files[$f]))
    }
    $freed = Remove-BuildLeftovers $port
    $left = @(Get-ChildItem $port -Recurse -File | ForEach-Object { $_.FullName.Substring($port.Length + 1) } | Sort-Object)
    Assert (($left -join ",") -eq "build\civrev.exe,build\civrev.map,src\port\keep.cpp") "Remove-BuildLeftovers keeps exe, map, port source (left: $($left -join ','))"
    Assert ($freed -eq 340) "Remove-BuildLeftovers returns bytes freed ($freed, want 340)"

    # ---- Get-VsInstallPath / Get-FreeGB ----
    $vs = Get-VsInstallPath
    Assert ($vs -and (Test-Path $vs)) "Get-VsInstallPath finds VS with Clang + CMake ($vs)"
    $gb = Get-FreeGB $tmp
    Assert ($gb -gt 0) "Get-FreeGB > 0 ($gb)"
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
if ($script:failed) { Write-Host "$script:failed FAILED" -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS"
exit 0
