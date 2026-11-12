@echo off
rem Civilization Revolution PC build kit: double-click to set everything up.
cd /d "%~dp0"
if not exist "civrev-port\setup\setup.ps1" (
  echo Setup.bat must run from the extracted kit folder.
  echo Extract the whole zip to a folder first, then run Setup.bat from there.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "civrev-port\setup\setup.ps1" %*
exit /b %errorlevel%
