@echo off
rem Launch the Civ Rev port. Double-clickable.
rem Expects the sibling folder layout from README.md:
rem   civrev-gamefiles\EBOOT.elf          decrypted game program
rem   civrev-gamefiles\vfs\PS3_GAME\...   disc contents ("/dev_bdvd" for the game)
rem Logs go to run.log / run.err.log next to this file.
setlocal
set "GAME=%~dp0..\civrev-gamefiles"
if not exist "%GAME%\EBOOT.elf" (
    echo Decrypted EBOOT not found: %GAME%\EBOOT.elf
    pause & exit /b 1
)
if not exist "%GAME%\vfs\PS3_GAME\PARAM.SFO" (
    echo Disc contents not found: %GAME%\vfs\PS3_GAME
    pause & exit /b 1
)
rem A running civrev.exe can't be replaced by a rebuild, and two copies would
rem share one save folder.
tasklist /FI "IMAGENAME eq civrev.exe" 2>nul | find /I "civrev.exe" >nul
if not errorlevel 1 (
    echo civrev.exe is already running. Close the game first, then run this again.
    pause & exit /b 1
)
rem Relink civrev.exe when the ps3recomp runtime library is newer than it (or it
rem is missing), so the game always runs the latest runtime fixes.
if defined PS3RECOMP_DIR (set "RTLIB=%PS3RECOMP_DIR%\build-release\ps3recomp_runtime.lib") else (set "RTLIB=%~dp0..\ps3recomp\build-release\ps3recomp_runtime.lib")
set "EXE=%~dp0build\civrev.exe"
powershell -NoProfile -Command "if (-not (Test-Path -LiteralPath $env:EXE)) { exit 1 }; if ((Test-Path -LiteralPath $env:RTLIB) -and ((Get-Item -LiteralPath $env:RTLIB).LastWriteTime -gt (Get-Item -LiteralPath $env:EXE).LastWriteTime)) { exit 1 }; exit 0"
if errorlevel 1 (
    echo civrev.exe is older than the ps3recomp runtime - rebuilding, about a minute...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
    if errorlevel 1 (
        echo Build failed - see the messages above.
        pause & exit /b 1
    )
)
set "PS3_VFS_ROOT=%GAME%\vfs"
rem Use ps3recomp's live-draw renderer. The default D3D12 backend draws this game
rem upside down (it ignores the guest's viewport Y sign) with wrong font glyphs.
if not defined RSX_LIVE_DRAW set "RSX_LIVE_DRAW=1"
rem Per-frame log lines are slow here: run.log is unbuffered, ~150 us a line
rem (measured), and the game wrote ~40 lines a frame. Set PS3_VERBOSE=1 for them.
if not defined PS3_VERBOSE set "PS3_VERBOSE=0"
rem Keep the logs of the last 10 runs in logs\ so a crash report survives the
rem next launch (newest run is always run.log / run.err.log).
set "HERE=%~dp0"
powershell -NoProfile -Command "$h=$env:HERE; $e=Join-Path $h 'run.err.log'; if (Test-Path -LiteralPath $e) { $d=Join-Path $h 'logs'; New-Item -ItemType Directory -Force -Path $d | Out-Null; $t=(Get-Item -LiteralPath $e).LastWriteTime.ToString('yyyy-MM-dd_HH-mm-ss'); Move-Item -LiteralPath $e -Destination (Join-Path $d ('run_'+$t+'.err.log')) -Force; $o=Join-Path $h 'run.log'; if (Test-Path -LiteralPath $o) { Move-Item -LiteralPath $o -Destination (Join-Path $d ('run_'+$t+'.log')) -Force }; Get-ChildItem -LiteralPath $d -Filter 'run_*.err.log' | Sort-Object Name -Descending | Select-Object -Skip 10 | ForEach-Object { Remove-Item -LiteralPath $_.FullName; $l=$_.FullName -replace '[.]err[.]log$','.log'; if (Test-Path -LiteralPath $l) { Remove-Item -LiteralPath $l } } }"
echo Running civrev.exe - close the game window to stop. Output: run.log, run.err.log
"%~dp0build\civrev.exe" "%GAME%\EBOOT.elf" %* > "%~dp0run.log" 2> "%~dp0run.err.log"
set "RC=%ERRORLEVEL%"
echo civrev.exe exited with code %RC%.
if not "%RC%"=="0" (
    echo.
    echo The game did not close normally - it probably crashed. Crash report:
    findstr /B /L /C:"[CRASH]" /C:"[ABORT]" /C:"[STACKOVERFLOW]" "%~dp0run.err.log"
    echo Please send run.err.log ^(next launch moves it into the logs folder^).
)
pause
