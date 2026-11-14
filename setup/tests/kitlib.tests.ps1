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

# PARAM.SFO with several UTF-8 entries (ordered key -> value), like a real one.
function New-TestSfoKeys([string]$Path, [Collections.Specialized.OrderedDictionary]$Values) {
    $keys = New-Object IO.MemoryStream; $data = New-Object IO.MemoryStream
    $entries = @()
    foreach ($k in $Values.Keys) {
        $v = [Text.Encoding]::UTF8.GetBytes([string]$Values[$k] + "`0")
        $max = [int]([Math]::Ceiling($v.Length / 4.0) * 4)
        $entries += , @([int]$keys.Position, $v.Length, $max, [int]$data.Position)
        $kb = [Text.Encoding]::ASCII.GetBytes("$k`0"); $keys.Write($kb, 0, $kb.Length)
        $data.Write($v, 0, $v.Length); $data.Write((New-Object byte[] ($max - $v.Length)), 0, $max - $v.Length)
    }
    while ($keys.Length % 4) { $keys.WriteByte(0) }
    $keyOff = 0x14 + 16 * $entries.Count
    $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
    $w.Write([byte[]](0, 0x50, 0x53, 0x46)); $w.Write([uint32]0x101)
    $w.Write([uint32]$keyOff); $w.Write([uint32]($keyOff + $keys.Length)); $w.Write([uint32]$entries.Count)
    foreach ($e in $entries) {
        $w.Write([uint16]$e[0]); $w.Write([uint16]0x0204); $w.Write([uint32]$e[1]); $w.Write([uint32]$e[2]); $w.Write([uint32]$e[3])
    }
    $w.Write($keys.ToArray()); $w.Write($data.ToArray()); $w.Flush()
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
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

    # ---- Get-SfoValue ----
    New-TestSfoKeys "$tmp\upd\PARAM.SFO" ([ordered]@{ CATEGORY = "GD"; APP_VER = "01.30"; TITLE_ID = "BLES00238"; VERSION = "01.00" })
    Assert ((Get-SfoValue "$tmp\upd\PARAM.SFO" "APP_VER") -eq "01.30") "Get-SfoValue APP_VER among several keys"
    Assert ((Get-SfoTitleId "$tmp\upd\PARAM.SFO") -eq "BLES00238") "Get-SfoTitleId among several keys"
    Assert ($null -eq (Get-SfoValue "$tmp\upd\PARAM.SFO" "NOPE")) "Get-SfoValue absent key -> null"
    # Optional real files: CIVREV_UPDATE_DIR = installed 1.30 update (<RPCS3>\dev_hdd0\game\BLES00238),
    # CIVREV_EBOOT_130 = decrypted 1.30 EBOOT.elf.
    $realUpd = $env:CIVREV_UPDATE_DIR
    if ($realUpd -and (Test-Path "$realUpd\PARAM.SFO")) { Assert ((Get-SfoValue "$realUpd\PARAM.SFO" "APP_VER") -eq "01.30") "Get-SfoValue real update PARAM.SFO -> 01.30" }
    else { Write-Host "SKIP real update PARAM.SFO not present" }

    # ---- Read-KitGameVersion ----
    New-Item -ItemType Directory -Force "$tmp\kv" | Out-Null
    Assert ((Read-KitGameVersion "$tmp\kv") -eq "1.0") "Read-KitGameVersion no file -> 1.0"
    Set-Content "$tmp\kv\game-version.txt" "1.30"
    Assert ((Read-KitGameVersion "$tmp\kv") -eq "1.30") "Read-KitGameVersion 1.30"
    Set-Content "$tmp\kv\game-version.txt" "2.0"
    $threw = $false; try { Read-KitGameVersion "$tmp\kv" | Out-Null } catch { $threw = $true }
    Assert $threw "Read-KitGameVersion unknown version -> throws"

    # ---- Get-EbootGameVersion ----
    Assert ($null -eq (Get-EbootGameVersion "$tmp\elf.elf")) "Get-EbootGameVersion unknown ELF -> null"
    Assert ($null -eq (Get-EbootGameVersion "$tmp\none.elf")) "Get-EbootGameVersion missing -> null"
    $elf10 = Join-Path $PSScriptRoot "..\..\..\civrev-gamefiles\EBOOT.elf"   # default sibling layout
    if (Test-Path $elf10) { Assert ((Get-EbootGameVersion $elf10) -eq "1.0") "Get-EbootGameVersion real 1.0 EBOOT" }
    else { Write-Host "SKIP real 1.0 EBOOT not present" }
    $elf130 = $env:CIVREV_EBOOT_130
    if ($elf130 -and (Test-Path $elf130)) { Assert ((Get-EbootGameVersion $elf130) -eq "1.30") "Get-EbootGameVersion real 1.30 EBOOT" }
    else { Write-Host "SKIP real 1.30 EBOOT not present" }

    # ---- Resolve-UpdateRoot ----
    Assert ((Resolve-UpdateRoot "$tmp\upd") -eq "$tmp\upd") "Resolve-UpdateRoot root"
    Assert ((Resolve-UpdateRoot "$tmp\upd\USRDIR") -eq "$tmp\upd") "Resolve-UpdateRoot USRDIR -> root"
    Assert ((Resolve-UpdateRoot "$tmp\upd\USRDIR\patch\") -eq "$tmp\upd") "Resolve-UpdateRoot USRDIR\patch\ -> root"

    # ---- Test-UpdateFolder (synthetic update: 2 patch files, 30 bytes) ----
    $v130 = $script:GameVersions["1.30"]
    $savedFiles = $v130.PatchFiles; $savedBytes = $v130.PatchBytes
    $v130.PatchFiles = 2; $v130.PatchBytes = 30
    try {
        Assert ((Test-UpdateFolder "$tmp\nothing" "BLES00238" "1.30") -eq "missing") "Test-UpdateFolder missing folder"
        New-Item -ItemType Directory -Force "$tmp\empty" | Out-Null
        Assert ((Test-UpdateFolder "$tmp\empty" "BLES00238" "1.30") -eq "no-sfo") "Test-UpdateFolder no PARAM.SFO"
        New-TestSfoKeys "$tmp\us\PARAM.SFO" ([ordered]@{ APP_VER = "01.30"; TITLE_ID = "BLUS30130" })
        Assert ((Test-UpdateFolder "$tmp\us" "BLES00238" "1.30") -eq "wrong-title") "Test-UpdateFolder other title"
        # The game's own data cache folder (RPCS3 before installing the update): no APP_VER.
        New-TestSfoKeys "$tmp\cache\PARAM.SFO" ([ordered]@{ CATEGORY = "GD"; TITLE_ID = "BLES00238"; VERSION = "01.00" })
        Assert ((Test-UpdateFolder "$tmp\cache" "BLES00238" "1.30") -eq "wrong-version") "Test-UpdateFolder data cache only (no APP_VER) -> wrong-version"
        Assert ((Test-UpdateFolder "$tmp\upd" "BLES00238" "1.30") -eq "no-patch") "Test-UpdateFolder no USRDIR\patch"
        New-Item -ItemType Directory -Force "$tmp\upd\USRDIR\patch" | Out-Null
        [IO.File]::WriteAllBytes("$tmp\upd\USRDIR\patch\a.xml", (New-Object byte[] 10))
        Assert ((Test-UpdateFolder "$tmp\upd" "BLES00238" "1.30") -eq "incomplete") "Test-UpdateFolder file missing -> incomplete"
        [IO.File]::WriteAllBytes("$tmp\upd\USRDIR\patch\b.dds", (New-Object byte[] 19))
        Assert ((Test-UpdateFolder "$tmp\upd" "BLES00238" "1.30") -eq "incomplete") "Test-UpdateFolder wrong size -> incomplete"
        [IO.File]::WriteAllBytes("$tmp\upd\USRDIR\patch\b.dds", (New-Object byte[] 20))
        Assert ((Test-UpdateFolder "$tmp\upd" "BLES00238" "1.30") -eq "ok") "Test-UpdateFolder complete -> ok"
    } finally { $v130.PatchFiles = $savedFiles; $v130.PatchBytes = $savedBytes }
    if ($realUpd -and (Test-Path "$realUpd\USRDIR\patch")) { Assert ((Test-UpdateFolder $realUpd "BLES00238" "1.30") -eq "ok") "Test-UpdateFolder real installed 1.30 update -> ok" }
    else { Write-Host "SKIP real installed update not present" }

    # ---- Copy-UpdateData / Remove-UpdateData ----
    $vfs = "$tmp\vfs"
    $cache = "$vfs\game\BLES00238"
    New-Item -ItemType Directory -Force "$cache\USRDIR" | Out-Null
    Set-Content "$cache\USRDIR\Common0.FPK" "game data cache"
    Set-Content "$tmp\upd\PS3LOGO.DAT" "logo"
    Copy-UpdateData "$tmp\upd" $vfs "BLES00238"
    Assert ((Get-SfoValue "$cache\PARAM.SFO" "APP_VER") -eq "01.30") "Copy-UpdateData copies the update's PARAM.SFO"
    Assert ((Test-Path "$cache\PS3LOGO.DAT") -and (Test-TreeCopied "$tmp\upd\USRDIR\patch" "$cache\USRDIR\patch")) "Copy-UpdateData copies PS3LOGO.DAT and USRDIR\patch"
    Copy-UpdateData "$tmp\upd" $vfs "BLES00238"
    Assert (Test-TreeCopied "$tmp\upd\USRDIR\patch" "$cache\USRDIR\patch") "Copy-UpdateData twice -> same files, no nested patch\patch"
    Assert (Remove-UpdateData $vfs "BLES00238") "Remove-UpdateData -> true"
    Assert (-not (Test-Path "$cache\USRDIR\patch") -and -not (Test-Path "$cache\PS3LOGO.DAT") -and -not (Test-Path "$cache\PARAM.SFO")) "Remove-UpdateData removes patch, logo, update PARAM.SFO"
    Assert (Test-Path "$cache\USRDIR\Common0.FPK") "Remove-UpdateData keeps the game's data cache"
    Assert (-not (Remove-UpdateData $vfs "BLES00238")) "Remove-UpdateData nothing left -> false"
    New-TestSfoKeys "$cache\PARAM.SFO" ([ordered]@{ CATEGORY = "GD"; TITLE_ID = "BLES00238" })
    [void](Remove-UpdateData $vfs "BLES00238")
    Assert (Test-Path "$cache\PARAM.SFO") "Remove-UpdateData keeps a PARAM.SFO without APP_VER (the game's own)"
    Assert (-not (Remove-UpdateData "$tmp\novfs" "BLES00238")) "Remove-UpdateData no folder -> false"

    # ---- Get-Rpcs3Hdd0 ----
    New-Item -ItemType Directory -Force "$tmp\emu\config" | Out-Null
    Assert ((Get-Rpcs3Hdd0 "$tmp\emu") -eq "$tmp\emu\dev_hdd0") "Get-Rpcs3Hdd0 default -> <RPCS3>\dev_hdd0"
    Set-Content "$tmp\emu\config\vfs.yml" @('$(EmulatorDir): ""', '/dev_hdd0/: $(EmulatorDir)dev_hdd0/', '/dev_hdd1/: $(EmulatorDir)dev_hdd1/')
    Assert ((Get-Rpcs3Hdd0 "$tmp\emu") -eq "$tmp\emu\dev_hdd0") "Get-Rpcs3Hdd0 vfs.yml with the default entry"
    Set-Content "$tmp\emu\config\vfs.yml" @('$(EmulatorDir): ""', '/dev_hdd0/: E:/PS3 Disk/hdd0/')
    Assert ((Get-Rpcs3Hdd0 "$tmp\emu") -eq "E:\PS3 Disk\hdd0") "Get-Rpcs3Hdd0 vfs.yml moved to another drive"
    Set-Content "$tmp\emu\config\vfs.yml" @('$(EmulatorDir): "F:/emu/"', '/dev_hdd0/: $(EmulatorDir)dev_hdd0/')
    Assert ((Get-Rpcs3Hdd0 "$tmp\emu") -eq "F:\emu\dev_hdd0") "Get-Rpcs3Hdd0 vfs.yml custom EmulatorDir"

    # ---- Find-UpdateRoot (synthetic complete update: 2 patch files, 30 bytes) ----
    $v130.PatchFiles = 2; $v130.PatchBytes = 30
    try {
        $hdd = "$tmp\rp\dev_hdd0\game\BLES00238"
        New-Item -ItemType Directory -Force "$hdd\USRDIR", "$tmp\rp\config", "$tmp\loose" | Out-Null
        Copy-Item "$tmp\upd\PARAM.SFO" "$hdd\PARAM.SFO"
        Copy-Item "$tmp\upd\USRDIR\patch" "$hdd\USRDIR\patch" -Recurse
        Set-Content "$hdd\USRDIR\EBOOT.elf" "x"; Set-Content "$tmp\loose\EBOOT.elf" "x"
        Assert ((Find-UpdateRoot "$hdd\USRDIR\EBOOT.elf" "BLES00238" "1.30") -eq $hdd) "Find-UpdateRoot EBOOT.elf decrypted next to the update -> found"
        Assert ($null -eq (Find-UpdateRoot "$tmp\loose\EBOOT.elf" "BLES00238" "1.30")) "Find-UpdateRoot EBOOT.elf moved away, no RPCS3 -> null"
        Assert ((Find-UpdateRoot "$tmp\loose\EBOOT.elf" "BLES00238" "1.30" @("$tmp\emu", "$tmp\rp")) -eq $hdd) "Find-UpdateRoot EBOOT.elf moved away -> found in RPCS3's dev_hdd0"
        Remove-Item "$hdd\USRDIR\patch\b.dds"
        Assert ($null -eq (Find-UpdateRoot "$hdd\USRDIR\EBOOT.elf" "BLES00238" "1.30" @("$tmp\rp"))) "Find-UpdateRoot incomplete update -> null"
    } finally { $v130.PatchFiles = $savedFiles; $v130.PatchBytes = $savedBytes }
    $env:CIVREV_NO_RPCS3_SEARCH = "1"
    Assert (@(Find-Rpcs3Dirs).Count -eq 0) "Find-Rpcs3Dirs CIVREV_NO_RPCS3_SEARCH=1 -> nothing"
    Remove-Item Env:\CIVREV_NO_RPCS3_SEARCH
    $dirs = @(Find-Rpcs3Dirs)
    Assert (@($dirs | Where-Object { -not (Test-Path (Join-Path $_ "rpcs3.exe")) }).Count -eq 0) "Find-Rpcs3Dirs returns only folders with rpcs3.exe ($($dirs.Count) found)"

    # ---- Get/Set-InstalledGameVersion, Reset-StepsForGameVersion ----
    $gk = "$tmp\gvkit"
    Assert ($null -eq (Get-InstalledGameVersion $gk)) "Get-InstalledGameVersion fresh folder -> null"
    Assert (-not (Reset-StepsForGameVersion $gk "1.30")) "Reset-StepsForGameVersion fresh folder -> false"
    $vdeps = "eboot", "lift", "compile"
    $vkeep = "disc", "menuart", "ps3recomp-source", "ps3recomp", "launcher", "extras"
    foreach ($m in $vdeps + $vkeep) { Set-StepDone $gk $m }
    Assert ((Get-InstalledGameVersion $gk) -eq "1.0") "Get-InstalledGameVersion pre-1.2 install (no stamp, EBOOT done) -> 1.0"
    Assert (-not (Reset-StepsForGameVersion $gk "1.0")) "Reset-StepsForGameVersion same version -> false"
    Assert (Reset-StepsForGameVersion $gk "1.30") "Reset-StepsForGameVersion 1.0 install, 1.30 kit -> true"
    Assert (@($vdeps | Where-Object { Test-StepDone $gk $_ }).Count -eq 0) "version switch clears update, eboot, lift, compile"
    Assert (@($vkeep | Where-Object { Test-StepDone $gk $_ }).Count -eq $vkeep.Count) "version switch keeps disc, menuart, runtime, launcher, extras"
    Set-InstalledGameVersion $gk "1.30"
    Assert ((Get-InstalledGameVersion $gk) -eq "1.30") "Set/Get-InstalledGameVersion 1.30"
    foreach ($m in $vdeps) { Set-StepDone $gk $m }
    Assert (-not (Reset-StepsForGameVersion $gk "1.30")) "Reset-StepsForGameVersion 1.30 install, 1.30 kit -> false"
    Assert (Reset-StepsForGameVersion $gk "1.0") "Reset-StepsForGameVersion 1.30 install, 1.0 kit -> true"

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

    # ---- Reset-StepsForNewRuntime (a newer kit pins another ps3recomp commit) ----
    $kr = "$tmp\kit"
    $shaA = "a" * 40; $shaB = "b" * 40
    $deps = "ps3recomp-source", "ps3recomp", "lift", "compile"
    $keep = "disc", "eboot", "menuart", "launcher", "extras"
    Assert (-not (Reset-StepsForNewRuntime $kr $shaA)) "Reset-StepsForNewRuntime fresh kit -> false"
    foreach ($m in $deps + $keep) { Set-StepDone $kr $m }
    Assert (Reset-StepsForNewRuntime $kr $shaA) "Reset-StepsForNewRuntime 1.0 install (no stamp) -> true"
    Assert (@($deps | Where-Object { Test-StepDone $kr $_ }).Count -eq 0) "Reset clears ps3recomp, lift and compile markers"
    Assert (@($keep | Where-Object { Test-StepDone $kr $_ }).Count -eq $keep.Count) "Reset keeps disc, eboot, menuart, launcher, extras"
    foreach ($m in $deps) { Set-StepDone $kr $m }
    Set-RuntimeStamp $kr $shaA
    Assert (-not (Reset-StepsForNewRuntime $kr $shaA)) "Reset-StepsForNewRuntime same commit -> false"
    Assert (@($deps | Where-Object { Test-StepDone $kr $_ }).Count -eq $deps.Count) "same commit keeps all markers"
    Assert (Reset-StepsForNewRuntime $kr $shaB) "Reset-StepsForNewRuntime other commit -> true"
    Assert (-not (Test-StepDone $kr "compile")) "other commit clears compile"

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
