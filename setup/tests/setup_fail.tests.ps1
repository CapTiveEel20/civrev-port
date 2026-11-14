<#
.SYNOPSIS
  Failure-path tests for setup\setup.ps1 and Setup.bat (plain PowerShell 5.1).
  Each case runs Setup in a fresh temp kit folder (with a space in its path) that
  holds a COPY of setup\ only; Setup must stop before any download or build.
  Exit 0 = all pass.
#>
$ErrorActionPreference = "Stop"
$setupDir = Split-Path $PSScriptRoot -Parent
$script:failed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "PASS $Msg" } else { Write-Host "FAIL $Msg" -ForegroundColor Red; $script:failed++ }
}

function New-TestSfo([string]$Path, [string]$Id) {
    $key = [Text.Encoding]::ASCII.GetBytes("TITLE_ID`0")
    $data = New-Object byte[] 16
    [Text.Encoding]::ASCII.GetBytes($Id).CopyTo($data, 0)
    $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
    $w.Write([byte[]](0, 0x50, 0x53, 0x46)); $w.Write([uint32]0x101)
    $w.Write([uint32]0x24); $w.Write([uint32]0x30); $w.Write([uint32]1)
    $w.Write([uint16]0); $w.Write([uint16]0x0204); $w.Write([uint32]($Id.Length + 1)); $w.Write([uint32]16); $w.Write([uint32]0)
    $w.Write($key); $w.Write((New-Object byte[] (12 - $key.Length))); $w.Write($data); $w.Flush()
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
    [IO.File]::WriteAllBytes($Path, $ms.ToArray())
}

# Small ISO from a folder with Windows' IMAPI2 (no extra tools needed).
function New-TestIso([string]$Folder, [string]$IsoPath) {
    if (-not ('IsoStreamWriter' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.IO; using System.Runtime.InteropServices.ComTypes;
public static class IsoStreamWriter {
    public static void Save(object stream, string path) {
        IStream s = (IStream)stream; byte[] buf = new byte[65536];
        IntPtr pRead = System.Runtime.InteropServices.Marshal.AllocHGlobal(4);
        try { using (FileStream f = File.Create(path)) { while (true) {
            s.Read(buf, buf.Length, pRead);
            int n = System.Runtime.InteropServices.Marshal.ReadInt32(pRead);
            if (n <= 0) break; f.Write(buf, 0, n); } } }
        finally { System.Runtime.InteropServices.Marshal.FreeHGlobal(pRead); }
    }
}
'@
    }
    $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $fsi.FileSystemsToCreate = 3      # ISO9660 + Joliet
    $fsi.VolumeName = "TESTDISC"
    $fsi.Root.AddTree($Folder, $false)
    [IsoStreamWriter]::Save($fsi.CreateResultImage().ImageStream, $IsoPath)
}

function New-Kit([string]$GameVersion = "") {
    $k = Join-Path $env:TEMP ("kit fail-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Force -Path "$k\civrev-port" | Out-Null
    Copy-Item -Recurse -LiteralPath $setupDir -Destination "$k\civrev-port\setup"
    if ($GameVersion) { Set-Content -LiteralPath "$k\civrev-port\setup\game-version.txt" -Value $GameVersion }
    return $k
}

function Invoke-Setup([string]$Kit, [string[]]$SetupArgs) {
    $ErrorActionPreference = "Continue"   # Setup's stderr must not abort the test run
    $ps1 = Join-Path $Kit "civrev-port\setup\setup.ps1"
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 @SetupArgs -Shortcut no -Cleanup no -NoPause 2>&1 | Out-String
    $log = ""
    if (Test-Path -LiteralPath "$Kit\setup.log") { $log = Get-Content -LiteralPath "$Kit\setup.log" -Raw }
    return @{ Code = $LASTEXITCODE; Out = $out; Log = $log }
}

$kits = @()
try {
    # ---- encrypted EBOOT ----
    $k = New-Kit; $kits += $k
    New-TestSfo "$k\disc\PS3_GAME\PARAM.SFO" "BLES00238"
    $enc = Join-Path $PSScriptRoot "..\..\..\civrev-gamefiles\EBOOT.BIN"   # default sibling layout
    if (-not (Test-Path $enc)) { $enc = "$k\EBOOT.BIN"; [IO.File]::WriteAllBytes($enc, [byte[]](0x53, 0x43, 0x45, 0, 1, 2, 3, 4)) }
    $r = Invoke-Setup $k @("-Disc", "$k\disc", "-Eboot", $enc)
    Assert ($r.Code -eq 1) "encrypted EBOOT -> exit 1 (got $($r.Code))"
    Assert ($r.Log -match "still encrypted") "encrypted EBOOT -> log says 'still encrypted'"
    Assert ($r.Log -match "Decrypt PS3 Binaries") "encrypted EBOOT -> log explains RPCS3 'Decrypt PS3 Binaries'"
    Assert (-not (Test-Path "$k\ps3recomp")) "encrypted EBOOT -> stopped before downloading ps3recomp"

    # ---- wrong disc (folder) ----
    $k = New-Kit; $kits += $k
    New-TestSfo "$k\disc\PS3_GAME\PARAM.SFO" "BLUS30130"
    $r = Invoke-Setup $k @("-Disc", "$k\disc", "-Eboot", $enc)
    Assert ($r.Code -eq 1) "wrong disc folder -> exit 1 (got $($r.Code))"
    Assert ($r.Log -match "BLUS30130" -and $r.Log -match "BLES00238") "wrong disc folder -> log names found and supported disc"
    Assert (-not (Test-Path "$k\civrev-gamefiles\vfs\PS3_GAME")) "wrong disc folder -> nothing copied"

    # ---- wrong disc (ISO): must be dismounted again ----
    $k = New-Kit; $kits += $k
    New-TestSfo "$k\iso-src\PS3_GAME\PARAM.SFO" "BLUS30130"
    $iso = "$k\wrong disc.iso"
    New-TestIso "$k\iso-src" $iso
    $r = Invoke-Setup $k @("-Disc", $iso, "-Eboot", $enc)
    Assert ($r.Code -eq 1) "wrong disc ISO -> exit 1 (got $($r.Code))"
    Assert ($r.Log -match "BLUS30130") "wrong disc ISO -> log names the found disc"
    Assert (-not (Get-DiskImage -ImagePath $iso).Attached) "wrong disc ISO -> image dismounted"

    # Optional real files (as in kitlib.tests.ps1): CIVREV_UPDATE_DIR = installed 1.30
    # update folder, CIVREV_EBOOT_130 = decrypted 1.30 EBOOT.elf.
    $elf10 = Join-Path $PSScriptRoot "..\..\..\civrev-gamefiles\EBOOT.elf"   # default sibling layout
    $realUpd = $env:CIVREV_UPDATE_DIR
    $elf130 = $env:CIVREV_EBOOT_130
    # Setup must not find this PC's own RPCS3: every case below controls where the update is.
    $env:CIVREV_NO_RPCS3_SEARCH = "1"

    # ---- unknown game version in the kit ----
    $k = New-Kit "9.9"; $kits += $k
    $r = Invoke-Setup $k @("-Disc", "$k\disc", "-Eboot", $enc)
    Assert ($r.Code -eq 1) "unknown game-version.txt -> exit 1 (got $($r.Code))"
    Assert ($r.Out -match "Unknown game version '9.9'") "unknown game-version.txt -> says so"
    # ---- both kits: the same 8 steps, the same two questions ----
    foreach ($gv in "1.0", "1.30") {
        $k = New-Kit $gv; $kits += $k
        New-TestSfo "$k\disc\PS3_GAME\PARAM.SFO" "BLES00238"
        $r = Invoke-Setup $k @("-Disc", "$k\disc", "-Eboot", $enc)
        Assert ($r.Log -match "Game version: $([regex]::Escape($gv))" -and $r.Log -match "3/8 Check your EBOOT" -and $r.Log -notmatch "/9 ") "$gv kit -> 8 steps, EBOOT is step 3/8"
        Assert ($r.Log -match "still encrypted") "$gv kit, encrypted EBOOT -> 'still encrypted'"
    }
    if ($elf130 -and (Test-Path $elf130) -and $realUpd -and (Test-Path "$realUpd\USRDIR\patch")) {
        # ---- 1.30 kit, the 1.30 EBOOT.elf alone (moved away from the update) ----
        $k = New-Kit "1.30"; $kits += $k
        New-TestSfo "$k\disc\PS3_GAME\PARAM.SFO" "BLES00238"
        New-Item -ItemType Directory -Force "$k\moved" | Out-Null
        Copy-Item -LiteralPath $elf130 -Destination "$k\moved\EBOOT.elf"
        $r = Invoke-Setup $k @("-Disc", "$k\disc", "-Eboot", "$k\moved\EBOOT.elf")
        Assert ($r.Code -eq 1) "1.30 kit, EBOOT.elf away from the update -> exit 1 (got $($r.Code))"
        Assert ($r.Log -match "cannot find the rest of the update" -and $r.Log -match "do not copy it elsewhere") "1.30 kit, update not found -> says to decrypt where RPCS3 installed it"
        Assert (-not (Test-Path "$k\civrev-gamefiles\EBOOT.elf")) "1.30 kit, update not found -> EBOOT.elf not taken"
        # ---- 1.30 kit, EBOOT.elf decrypted where RPCS3 installed the update: found by itself ----
        $k = New-Kit "1.30"; $kits += $k
        New-TestSfo "$k\disc\PS3_GAME\PARAM.SFO" "BLES00238"
        $usr = "$k\My RPCS3\dev_hdd0\game\BLES00238\USRDIR"
        New-Item -ItemType Directory -Force $usr | Out-Null
        Copy-Item -LiteralPath "$realUpd\PARAM.SFO" -Destination "$k\My RPCS3\dev_hdd0\game\BLES00238\"
        Copy-Item -LiteralPath "$realUpd\USRDIR\patch" -Destination "$usr\patch" -Recurse
        Copy-Item -LiteralPath $elf130 -Destination "$usr\EBOOT.elf"
        $r = Invoke-Setup $k @("-Disc", "$k\disc", "-Eboot", "$usr\EBOOT.elf")
        Assert ($r.Log.Contains("Update files: $k\My RPCS3\dev_hdd0\game\BLES00238")) "1.30 kit, EBOOT.elf next to the update -> update found without asking"
        Assert ((Get-ChildItem "$k\civrev-gamefiles\vfs\game\BLES00238\USRDIR\patch" -File).Count -eq 23) "1.30 kit -> update's 23 files copied"
        Assert ((Get-ChildItem "$k\civrev-gamefiles\EBOOT.elf").Length -gt 0 -and $r.Log -match "4/8 Tidy") "1.30 kit -> EBOOT step done, Setup goes on (stops at the test disc's missing menu art)"
        Assert (-not (Test-Path "$k\ps3recomp")) "1.30 kit -> test stopped before downloading ps3recomp"
        # ---- the same folder, now with the 1.0 kit: update data removed, version switch noticed ----
        Set-Content -LiteralPath "$k\civrev-port\setup\game-version.txt" -Value "1.0"
        $r = Invoke-Setup $k @("-Disc", "$k\disc", "-Eboot", $enc)
        Assert ($r.Log -match "set up for game version 1.30; this kit builds game version 1.0") "1.0 kit over a 1.30 folder -> version switch noticed"
        Assert ($r.Log -match "Check your EBOOT" -and $r.Log -notmatch "Check your EBOOT : already done") "1.0 kit over a 1.30 folder -> EBOOT step redone"
        Assert (-not (Test-Path "$k\civrev-gamefiles\vfs\game\BLES00238\USRDIR\patch")) "1.0 kit over a 1.30 folder -> update data removed"
    } else { Write-Host "SKIP 1.30 update search (set CIVREV_EBOOT_130 and CIVREV_UPDATE_DIR)" }
    # ---- 1.30 kit given the 1.0 EBOOT ----
    if (Test-Path $elf10) {
        $k = New-Kit "1.30"; $kits += $k
        New-TestSfo "$k\disc\PS3_GAME\PARAM.SFO" "BLES00238"
        $r = Invoke-Setup $k @("-Disc", "$k\disc", "-Eboot", $elf10)
        Assert ($r.Code -eq 1 -and $r.Log -match "is game version 1.0, but this kit builds game version 1.30") "1.30 kit + 1.0 EBOOT -> names both versions"
        Assert ($r.Log -match "game1.0.zip") "1.30 kit + 1.0 EBOOT -> points to the 1.0 kit"
    } else { Write-Host "SKIP 1.30 kit + 1.0 EBOOT (needs ..\civrev-gamefiles\EBOOT.elf)" }
    # ---- 1.0 kit given the 1.30 EBOOT ----
    if ($elf130 -and (Test-Path $elf130)) {
        $k = New-Kit "1.0"; $kits += $k
        New-TestSfo "$k\disc\PS3_GAME\PARAM.SFO" "BLES00238"
        $r = Invoke-Setup $k @("-Disc", "$k\disc", "-Eboot", $elf130)
        Assert ($r.Code -eq 1 -and $r.Log -match "is game version 1.30, but this kit builds game version 1.0") "1.0 kit + 1.30 EBOOT -> names both versions"
        Assert ($r.Log -match "game1.30.zip") "1.0 kit + 1.30 EBOOT -> points to the 1.30 kit"
    } else { Write-Host "SKIP 1.0 kit + 1.30 EBOOT (set CIVREV_EBOOT_130)" }

    # ---- Setup.bat outside an extracted kit ----
    $k = Join-Path $env:TEMP ("kit bat-" + [guid]::NewGuid().ToString("N").Substring(0, 8)); $kits += $k
    New-Item -ItemType Directory -Force -Path $k | Out-Null
    Copy-Item -LiteralPath "$setupDir\Setup.bat" -Destination $k
    $ErrorActionPreference = "Continue"
    # Full path, empty stdin for 'pause' (nested quotes for cmd get mangled by PowerShell 5.1).
    $out = '' | cmd /c "$k\Setup.bat" 2>&1 | Out-String
    $ErrorActionPreference = "Stop"
    Assert ($out -match "Extract the whole zip") "Setup.bat alone -> 'Extract the whole zip' message"
}
finally {
    foreach ($k in $kits) {
        Get-ChildItem -LiteralPath $k -Filter *.iso -ErrorAction SilentlyContinue | ForEach-Object {
            Dismount-DiskImage -ImagePath $_.FullName -ErrorAction SilentlyContinue | Out-Null }
        Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction SilentlyContinue
    }
}
if ($script:failed) { Write-Host "$script:failed FAILED" -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS"
exit 0
