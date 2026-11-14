<#
.SYNOPSIS
  Civilization Revolution PC build kit: turns YOUR disc + decrypted EBOOT into
  a playable CivRev.exe. Started by Setup.bat; never starts the game itself.

  Kit layout (all side by side in <KitRoot>):
    civrev-port\        port scripts and sources (this folder's parent)
    ps3recomp\          downloaded here at the pinned commit (setup\ps3recomp.lock)
    civrev-gamefiles\   EBOOT.elf + vfs\PS3_GAME\ copied from your disc
                        (+ vfs\game\BLES00238\ for game 1.30: the update's own
                        files, found next to the EBOOT.elf or in RPCS3's dev_hdd0)
    setup.log           everything Setup did; send it when asking for help

  The game version this kit builds (1.0 or 1.30) is in setup\game-version.txt.
  Re-running Setup skips finished steps (markers in <KitRoot>\.setup\).

.EXAMPLE
  Setup.bat
  Setup.bat -Disc "D:\Games\CivRev.iso" -Eboot "D:\EBOOT.elf" -Shortcut yes -Cleanup no
#>
param(
    [string]$KitRoot,
    [string]$Disc,                                  # .iso file, or folder holding PS3_GAME\
    [string]$Update,                                # game 1.30 only, optional: the installed update folder (normally found by itself)
    [string]$Eboot,                                 # decrypted EBOOT.elf
    [ValidateSet("", "yes", "no")][string]$Shortcut = "",
    [ValidateSet("", "yes", "no")][string]$Cleanup = "",
    [ValidateSet("", "yes", "no")][string]$InstallTools = "",  # install missing VS Build Tools / Python with winget
    [switch]$ShowAll,                               # print every tool line on screen (it always goes to setup.log)
    [switch]$NoPause
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "kitlib.ps1")

$TitleId   = "BLES00238"
$MinFreeGB = 10
try { $GameVersion = Read-KitGameVersion $PSScriptRoot }
catch { Write-Host $_.Exception.Message -ForegroundColor Red; if (-not $NoPause) { Read-Host "Press Enter to close this window" | Out-Null }; exit 1 }
$EbootSha  = $script:GameVersions[$GameVersion].EbootSha
$IsUpdate  = $GameVersion -ne "1.0"
if (-not $KitRoot) { $KitRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
$KitRoot = [IO.Path]::GetFullPath($KitRoot)
$Port = Join-Path $KitRoot "civrev-port"
$Rc   = Join-Path $KitRoot "ps3recomp"
$Game = Join-Path $KitRoot "civrev-gamefiles"
$Vfs  = Join-Path $Game "vfs"
$Log  = Join-Path $KitRoot "setup.log"

# ---------------------------------------------------------------- output ----
function Log([string]$Msg, [string]$Color = "Gray") {
    Write-Host $Msg -ForegroundColor $Color
    Add-Content -LiteralPath $Log -Value $Msg
}

function Wait-Key {
    if (-not $NoPause) { Write-Host ""; Read-Host "Press Enter to close this window" | Out-Null }
}

function Fail([string]$Step, [string]$Msg) {
    Log "" ; Log "SETUP STOPPED in step: $Step" Red
    Log $Msg Yellow
    Write-Host ""
    if (-not $script:FailDetailsShown) {
        Write-Host "---- last lines of setup.log ----" -ForegroundColor DarkGray
        Get-Content -LiteralPath $Log -Tail 30 | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    }
    Write-Host "Full log: $Log" -ForegroundColor DarkGray
    Write-Host "Fix the problem above, then run Setup.bat again: finished steps are skipped."
    Wait-Key
    exit 1
}

# Run a program. Every line it prints goes to setup.log. The screen shows only
# a progress line (compile: "N of M files (P%)", else seconds elapsed) and the
# kit scripts' own "==>" step names: compilers print thousands of harmless
# warnings that would only alarm players. -ShowAll prints everything.
# Throws on a non-zero exit; the message carries the tool's error lines.
function Invoke-Logged([string]$What, [string]$Exe, [string[]]$Arguments) {
    $ErrorActionPreference = "Continue"     # stderr lines are normal output here
    $errs = New-Object Collections.Generic.List[string]
    $tail = New-Object Collections.Generic.Queue[string]
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $ui = @{ Open = $false; Next = 0.0; Ninja = $false }
    $writer = New-Object IO.StreamWriter($Log, $true)
    try {
        & $Exe @Arguments 2>&1 | ForEach-Object {
            $line = "$_"
            $writer.WriteLine($line)
            if ($ShowAll) { Write-Host $line; return }
            $kind = Get-OutputLineKind $line
            if ($kind -eq "error") { $errs.Add($line) }
            $tail.Enqueue($line); if ($tail.Count -gt 15) { [void]$tail.Dequeue() }
            $text = $null
            if ($kind -eq "status") {
                if ($ui.Open) { Write-Host ""; $ui.Open = $false }
                Write-Host ("   " + $line.Substring(4))
                $ui.Next = 0.0
            } elseif ($kind -eq "progress") {
                $p = Get-NinjaProgress $line; $ui.Ninja = $true
                $text = "{0}: {1} of {2} files ({3}%)" -f $What, $p[0], $p[1], [int][Math]::Floor(100 * $p[0] / $p[1])
            } elseif (-not $ui.Ninja -and $clock.Elapsed.TotalSeconds -ge $ui.Next) {
                $text = "{0}... {1:N0} s" -f $What, $clock.Elapsed.TotalSeconds
                $ui.Next = $clock.Elapsed.TotalSeconds + 1
            }
            if ($text) { Write-Host -NoNewline ("`r   " + $text).PadRight(78); $ui.Open = $true }
        }
        $code = $LASTEXITCODE
    } finally {
        $writer.Dispose()
    }
    if ($ui.Open) { Write-Host "" }
    if ($code -ne 0) {
        $shown = @($tail)
        if ($errs.Count) { $shown = @($errs | Select-Object -First 12) }
        $script:FailDetailsShown = $true
        throw ("$What failed (exit code $code). What went wrong:`n    " + ($shown -join "`n    "))
    }
}

function Invoke-Script([string]$What, [string]$Script, [string[]]$Arguments = @()) {
    Invoke-Logged $What "powershell.exe" (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Script) + $Arguments)
}

function Invoke-Step([string]$Name, [string]$Marker, [scriptblock]$Body) {
    if ($Marker -and (Test-StepDone $KitRoot $Marker)) { Log "== $Name : already done, skipped" DarkGray; return }
    Log "" ; Log "== $Name" Cyan
    $script:FailDetailsShown = $false
    $t = [Diagnostics.Stopwatch]::StartNew()
    try { & $Body } catch { Fail $Name $_.Exception.Message }
    if ($Marker) { Set-StepDone $KitRoot $Marker }
    Log ("   done in {0:N0} s" -f $t.Elapsed.TotalSeconds) DarkGray
}

function Ask-YesNo([string]$Question, [bool]$Default) {
    $hint = "y/N"; if ($Default) { $hint = "Y/n" }
    while ($true) {
        $a = (Read-Host "$Question [$hint]").Trim().ToLower()
        if ($a -eq "") { return $Default }
        if ($a -in "y", "yes", "s", "si") { return $true }
        if ($a -in "n", "no") { return $false }
    }
}

function Pick-File([string]$Title, [string]$Filter) {
    Add-Type -AssemblyName System.Windows.Forms
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Title = $Title; $d.Filter = $Filter
    if ($d.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw "No file chosen." }
    return $d.FileName
}

function Pick-Folder([string]$Title) {
    Add-Type -AssemblyName System.Windows.Forms
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = $Title
    if ($d.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw "No folder chosen." }
    return $d.SelectedPath
}

# ----------------------------------------------------------------- steps ----
$InstallToolsText = @"

Setup needs two free programs that are not on this PC yet:
{0}
Setup can install them for you now with winget, the app installer built into
Windows. They come straight from Microsoft and python.org.
  - Up to about 5 GB to download; 10 to 30 minutes.
  - Windows asks once "Do you want to allow this app to make changes to your
    device?": answer Yes. An installer window shows its progress.
"@

# Offer to install missing Visual Studio Build Tools / Python with winget.
function Install-MissingTools([bool]$NeedVs, [bool]$NeedPython) {
    $plan = @(Get-ToolInstallPlan $NeedVs $NeedPython)
    if ($InstallTools -eq "no" -or $plan.Count -eq 0) { return }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Log "   winget (Windows' app installer) is not available here, so the tools must be installed by hand." Yellow
        return
    }
    if ($InstallTools -ne "yes") {
        Write-Host ($InstallToolsText -f (($plan | ForEach-Object { "  - " + $_.What }) -join "`n"))
        if (-not (Ask-YesNo "Install them now?" $true)) { return }
    }
    foreach ($p in $plan) {
        Log "   Installing $($p.What)..."
        try { Invoke-Logged "Installing $($p.What)" "winget" $p.Args }
        catch { Log "   $($_.Exception.Message)" Yellow }     # checked again below
    }
    # The installers changed PATH for new windows; give this one the new PATH too.
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    $script:FailDetailsShown = $false
}

function Test-Tools {
    $missing = @()
    if (-not [Environment]::Is64BitOperatingSystem) { $missing += "A 64-bit Windows 10 or 11." }
    if (-not (Test-StepDone $KitRoot "compile")) {
        $free = Get-FreeGB $KitRoot
        if ($free -lt $MinFreeGB) { $missing += "At least $MinFreeGB GB free on this drive (now $free GB)." }
    }
    $needVs = -not (Get-VsInstallPath)
    $needPy = -not (Find-Python)
    if (($needVs -or $needPy) -and -not $missing.Count) { Install-MissingTools $needVs $needPy }
    if (-not (Get-VsInstallPath)) {
        $missing += "Visual Studio 2022 (Community is free) with these parts ticked in the Visual Studio Installer:`n" +
                    "      - Workload 'Desktop development with C++'`n" +
                    "      - Individual component 'C++ Clang Compiler for Windows'`n" +
                    "      - Individual component 'C++ CMake tools for Windows'`n" +
                    "    Download: https://visualstudio.microsoft.com/downloads/"
    }
    $script:Python = Find-Python
    if (-not $script:Python) {
        $missing += "Python 3.10 or newer from https://www.python.org/downloads/ (tick 'Add python.exe to PATH' in the installer)."
    }
    if ($missing.Count) { throw ("Missing:`n  - " + ($missing -join "`n  - ") + "`nInstall them, then run Setup.bat again.") }
    Log "   Visual Studio: $(Get-VsInstallPath)"
    Log "   Python: $script:Python"
}

function Copy-DiscFrom([string]$Root) {
    $sfo = Join-Path $Root "PS3_GAME\PARAM.SFO"
    $id = Get-SfoTitleId $sfo
    if (-not $id) { throw "No PS3_GAME\PARAM.SFO found in '$Root'. Choose the disc .iso, or the folder that contains PS3_GAME." }
    if ($id -ne $TitleId) {
        throw "This disc is '$id'. Only the European disc $TitleId is supported (the port is built for that exact version)."
    }
    Log "   Disc: $id, copying PS3_GAME (about 5 GB, a few minutes)..."
    $dst = Join-Path $Vfs "PS3_GAME"
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    $ErrorActionPreference = "Continue"
    robocopy (Join-Path $Root "PS3_GAME") $dst /E /R:1 /W:1 /NP /NFL /NDL /A-:R | ForEach-Object { Add-Content -LiteralPath $Log -Value "$_" }
    $rc = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    if ($rc -ge 8) { throw "Copying the disc failed (robocopy code $rc). See setup.log." }
    $sfb = Join-Path $Root "PS3_DISC.SFB"
    if (Test-Path -LiteralPath $sfb) { Copy-Item -LiteralPath $sfb -Destination $Vfs -Force }
    if (-not (Test-TreeCopied (Join-Path $Root "PS3_GAME") $dst)) { throw "The copied disc files do not match the source. Run Setup again." }
    Get-ChildItem -LiteralPath $Vfs -Recurse -File | Where-Object { $_.IsReadOnly } | ForEach-Object { $_.IsReadOnly = $false }
}

function Copy-Disc {
    $src = $Disc
    if (-not $src) {
        Write-Host "Your game disc: choose the .iso file, or (Cancel) a folder that contains PS3_GAME."
        try { $src = Pick-File "Choose your Civilization Revolution disc image (.iso)" "Disc image (*.iso)|*.iso" }
        catch { $src = Pick-Folder "Choose the folder that contains PS3_GAME" }
    }
    Log "   Source: $src"
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        $img = Mount-DiskImage -ImagePath $src -PassThru
        try {
            $letter = ($img | Get-Volume).DriveLetter
            if (-not $letter) { throw "Windows mounted the image but gave it no drive letter." }
            Copy-DiscFrom "${letter}:\"
        } finally {
            Dismount-DiskImage -ImagePath $src | Out-Null
        }
    } elseif (Test-Path -LiteralPath $src -PathType Container) {
        if ((Split-Path $src -Leaf) -ieq "PS3_GAME") { $src = Split-Path $src -Parent }
        Copy-DiscFrom $src
    } else {
        throw "Not found: $src"
    }
}

# Where the EBOOT.BIN to decrypt comes from, for this kit's game version.
$EbootBinSource = "the disc's PS3_GAME\USRDIR\EBOOT.BIN"
if ($IsUpdate) { $EbootBinSource = "the update's EBOOT.BIN where RPCS3 installed it: <RPCS3 folder>\dev_hdd0\game\$TitleId\USRDIR\EBOOT.BIN" }

# Game 1.30: the update is the new program (EBOOT) PLUS its own data files
# (USRDIR\patch\: menus, translated text, models), which the 1.30 game needs and
# which are not on the disc. Find them without asking (Find-UpdateRoot: next to
# the EBOOT.elf, then RPCS3's dev_hdd0), or the folder given with -Update.
function Find-Update([string]$ElfPath) {
    if ($Update) {
        $root = Resolve-UpdateRoot $Update
        $why = Test-UpdateFolder $root $TitleId $GameVersion
        if ($why -ne "ok") { throw "-Update '$root' is not the complete game update ${GameVersion} ($why)." }
        return $root
    }
    $rpcs3 = @(Find-Rpcs3Dirs)
    foreach ($d in $rpcs3) { Log "   RPCS3 found: $d" }
    $root = Find-UpdateRoot $ElfPath $TitleId $GameVersion $rpcs3
    if (-not $root) {
        throw "Your EBOOT.elf is game version $GameVersion, but Setup cannot find the rest of the update.`n" +
              "The $GameVersion update is the new program PLUS its own files (menus, text, models), which the game needs.`n" +
              "Setup looks for them next to your EBOOT.elf and in your RPCS3 folder. To fix it:`n" +
              "  1. In RPCS3: File > Install Packages/Raps/Edats, choose the game's $GameVersion update package (.pkg).`n" +
              "  2. In RPCS3: Utilities > Decrypt PS3 Binaries, choose $EbootBinSource`n" +
              "     (right there, do not copy it elsewhere first).`n" +
              "  3. Run Setup.bat again and choose the EBOOT.elf that RPCS3 writes next to it."
    }
    return $root
}

function Copy-Eboot {
    $dst = Join-Path $Game "EBOOT.elf"
    $src = $Eboot
    if (-not $src) {
        Write-Host "Your decrypted EBOOT.elf for game version $GameVersion (made with RPCS3: Utilities > Decrypt PS3 Binaries,"
        Write-Host "from $EbootBinSource)."
        $src = Pick-File "Choose your decrypted EBOOT.elf (game version $GameVersion)" "Decrypted EBOOT (*.elf)|*.elf|All files (*.*)|*.*"
    }
    Log "   EBOOT: $src"
    switch (Test-EbootFile $src $EbootSha) {
        "ok" { }
        "missing" { throw "File not found: $src" }
        "encrypted" {
            throw "This EBOOT is still encrypted (it is an EBOOT.BIN, not the decrypted EBOOT.elf).`n" +
                  "Decrypt it with RPCS3: Utilities > Decrypt PS3 Binaries, choose $EbootBinSource,`n" +
                  "then give Setup the EBOOT.elf that RPCS3 writes next to it."
        }
        "not-elf" { throw "This is not a PS3 program file (no ELF header): $src" }
        "wrong-version" {
            $other = Get-EbootGameVersion $src
            if ($other) {
                throw "This EBOOT.elf is game version $other, but this kit builds game version $GameVersion.`n" +
                      "Either give Setup the EBOOT.elf decrypted from $EbootBinSource,`n" +
                      "or download the kit for game version $other (CivRevPC-<kit version>-game$other.zip)."
            }
            throw "This EBOOT.elf is not a known version of the game. This kit needs game version $GameVersion of the European disc ${TitleId}:`n" +
                  "decrypt $EbootBinSource with RPCS3."
        }
    }
    $updateRoot = $null
    if ($IsUpdate) { $updateRoot = Find-Update $src; Log "   Update files: $updateRoot" }
    New-Item -ItemType Directory -Force -Path $Game | Out-Null
    if ([IO.Path]::GetFullPath($src) -ne $dst) { Copy-Item -LiteralPath $src -Destination $dst -Force }
    if ($updateRoot) { Copy-UpdateData $updateRoot $Vfs $TitleId }
}

function Get-Ps3Recomp {
    $sha = Read-LockSha (Join-Path $PSScriptRoot "ps3recomp.lock")
    if (-not (Test-StepDone $KitRoot "ps3recomp-source")) {
        $url = "https://github.com/CapTiveEel20/ps3recomp/archive/$sha.zip"
        $zip = Join-Path $KitRoot ".setup\ps3recomp.zip"
        $tmp = Join-Path $KitRoot ".setup\unzip"
        New-Item -ItemType Directory -Force -Path (Split-Path $zip) | Out-Null
        Remove-Item -LiteralPath $tmp, $Rc -Recurse -Force -ErrorAction SilentlyContinue
        Log "   Downloading ps3recomp $($sha.Substring(0, 8))..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp
        Move-Item -LiteralPath (Join-Path $tmp "ps3recomp-$sha") -Destination $Rc
        Remove-Item -LiteralPath $tmp, $zip -Recurse -Force
        Set-RuntimeStamp $KitRoot $sha
        Set-StepDone $KitRoot "ps3recomp-source"
    }
    $venvPy = Join-Path $Rc ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $venvPy)) {
        Invoke-Logged "Creating the Python environment" $script:Python @("-m", "venv", (Join-Path $Rc ".venv"))
    }
    Invoke-Logged "Installing Python packages" $venvPy @("-m", "pip", "install", "--disable-pip-version-check", "-r", (Join-Path $Rc "requirements.txt"))
    Import-VsDevEnv (Get-VsInstallPath)
    $bld = Join-Path $Rc "build-release"
    Invoke-Logged "Configuring the ps3recomp runtime" "cmake" @("-S", $Rc, "-B", $bld, "-G", "Ninja",
        "-DCMAKE_C_COMPILER=clang-cl", "-DCMAKE_CXX_COMPILER=clang-cl", "-DCMAKE_BUILD_TYPE=Release")
    Invoke-Logged "Building the ps3recomp runtime" "cmake" @("--build", $bld, "--target", "ps3recomp_runtime")
    if (-not (Test-Path -LiteralPath (Join-Path $bld "ps3recomp_runtime.lib"))) { throw "ps3recomp_runtime.lib was not built." }
}

function New-DesktopShortcut {
    $lnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "Civilization Revolution.lnk"
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = Join-Path $Port "CivRev.exe"
    $s.WorkingDirectory = $Port
    $s.IconLocation = (Join-Path $Port "CivRev.exe") + ",0"
    $s.Save()
    Log "   Shortcut: $lnk"
}

$CleanupText = @"
Delete the build leftovers (about 1.1 GB)?
  The game works either way.
  Yes: frees about 1.1 GB, but if you ever run Setup again (for example for a
       newer kit) it must redo code generation and compiling (10 minutes or more).
  No (recommended): keeps them, so a later re-run or update is quicker.
"@

function Invoke-Extras {
    $doShortcut = $Shortcut -eq "yes"
    if ($Shortcut -eq "") { $doShortcut = Ask-YesNo "Create a desktop shortcut to the game?" $true }
    if ($doShortcut) { New-DesktopShortcut }

    $doCleanup = $Cleanup -eq "yes"
    if ($Cleanup -eq "") { Write-Host $CleanupText; $doCleanup = Ask-YesNo "Delete the build leftovers?" $false }
    if ($doCleanup) {
        $freed = Remove-BuildLeftovers $Port
        Clear-StepDone $KitRoot "lift"
        Clear-StepDone $KitRoot "compile"
        Log ("   Build leftovers deleted: {0:N1} GB freed." -f ($freed / 1GB))
    }
}

# ------------------------------------------------------------------ main ----
New-Item -ItemType Directory -Force -Path $KitRoot | Out-Null
Log "" ; Log "==== Civilization Revolution PC build kit - Setup $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====" White
Log "Kit folder: $KitRoot"
Log "Game version: $GameVersion"
if (-not (Test-Path -LiteralPath (Join-Path $Port "setup\setup.ps1"))) { Fail "start" "civrev-port\ not found in $KitRoot." }
if (Reset-StepsForNewRuntime $KitRoot (Read-LockSha (Join-Path $PSScriptRoot "ps3recomp.lock"))) {
    Log "This kit is newer than your install: Setup downloads the new ps3recomp runtime" Cyan
    Log "and rebuilds the game. Your disc copy and your saves are kept." Cyan
}
$hadVersion = Get-InstalledGameVersion $KitRoot
if (Reset-StepsForGameVersion $KitRoot $GameVersion) {
    Log "This folder was set up for game version $hadVersion; this kit builds game version $GameVersion." Cyan
    Log "Setup asks for the matching files and rebuilds the game. Your disc copy and your saves are kept." Cyan
}
if (-not $IsUpdate -and (Remove-UpdateData $Vfs $TitleId)) { Log "   Removed the game update's files (this kit builds game version 1.0)." }
Set-InstalledGameVersion $KitRoot $GameVersion

# Steps: name, marker (finished steps are skipped on a re-run), body.
$steps = @(
    @("Check tools", "", { Test-Tools }),
    @("Copy your game disc", "disc", { Copy-Disc })
)
$steps += @(
    @("Check your EBOOT", "eboot", { Copy-Eboot }),
    @("Tidy the multiplayer menu art", "menuart", {
        Invoke-Logged "Menu art" $script:Python @((Join-Path $Port "tools\patch_menu_assets.py"), $Vfs)
    }),
    @("ps3recomp runtime", "ps3recomp", { Get-Ps3Recomp }),
    @("Generate code from your EBOOT (a few minutes)", "lift", {
        Invoke-Script "Code generation" (Join-Path $Port "tools\relift.ps1") @("-PS3Recomp", $Rc, "-Elf", (Join-Path $Game "EBOOT.elf"))
    }),
    @("Compile the game (5 to 30+ minutes, depends on your CPU)", "compile", {
        Invoke-Script "Compiling" (Join-Path $Port "build.ps1")
        if (-not (Test-Path -LiteralPath (Join-Path $Port "build\civrev.exe"))) { throw "build\civrev.exe was not produced." }
    }),
    @("Build the launcher", "launcher", {
        Invoke-Script "Launcher" (Join-Path $Port "launcher\build_launcher.ps1")
    })
)
$env:PS3RECOMP_DIR = $Rc
for ($i = 0; $i -lt $steps.Count; $i++) {
    Invoke-Step ("{0}/{1} {2}" -f ($i + 1), $steps.Count, $steps[$i][0]) $steps[$i][1] $steps[$i][2]
}
Invoke-Step "Extras" "extras" { Invoke-Extras }

$exe = Join-Path $Port "CivRev.exe"
Log "" ; Log "DONE. Start the game with: $exe" Green
Log "Your settings: $(Join-Path $Port 'CivRev.ini') (created on first start). Logs: $(Join-Path $Port 'run.err.log')"
if (-not $NoPause) {
    if (Ask-YesNo "Open the game folder now?" $true) { Start-Process explorer.exe $Port }
}
exit 0
