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

function New-Kit {
    $k = Join-Path $env:TEMP ("kit fail-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Force -Path "$k\civrev-port" | Out-Null
    Copy-Item -Recurse -LiteralPath $setupDir -Destination "$k\civrev-port\setup"
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
