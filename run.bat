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
set "PS3_VFS_ROOT=%GAME%\vfs"
rem Use ps3recomp's live-draw renderer. The default D3D12 backend draws this game
rem upside down (it ignores the guest's viewport Y sign) with wrong font glyphs.
if not defined RSX_LIVE_DRAW set "RSX_LIVE_DRAW=1"
echo Running civrev.exe - close the game window to stop. Output: run.log, run.err.log
"%~dp0build\civrev.exe" "%GAME%\EBOOT.elf" %* > "%~dp0run.log" 2> "%~dp0run.err.log"
echo civrev.exe exited with code %ERRORLEVEL%.
pause
