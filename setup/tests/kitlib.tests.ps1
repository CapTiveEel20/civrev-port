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
    Assert ($null -eq (Find-Python @(, @('no-such-python-xyz')))) "Find-Python unknown command -> null"
    Assert ($null -eq (Find-Python @(, @('cmd', '/c', 'exit 1')))) "Find-Python failing command -> null"
    $py = Find-Python
    Assert ($py -and (Test-Path $py)) "Find-Python default finds an interpreter ($py)"

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
