Sid Meier's Civilization Revolution (PS3) - PC build kit
=========================================================

This kit turns YOUR OWN copy of the PS3 game into a native Windows program.
It contains no game code, art or keys: everything game-specific is made on
your PC from your disc. Only the European disc BLES00238 is supported.


WHAT YOU NEED
-------------
1. Your game disc as an .iso file, or the extracted disc folder
   (the folder that contains PS3_GAME and PS3_DISC.SFB).

2. The decrypted game program, EBOOT.elf. Make it with the RPCS3 emulator
   (https://rpcs3.net): Utilities > Decrypt PS3 Binaries, choose the disc's
   PS3_GAME\USRDIR\EBOOT.BIN. RPCS3 writes EBOOT.elf next to it.
   (Setup refuses the still-encrypted EBOOT.BIN and other game versions.)

3. Two free programs that build the game: Visual Studio 2022 Build Tools
   (Microsoft's C++ compiler) and Python. You do not need to get them
   yourself: if they are missing, Setup offers to install them for you
   (answer Y). That downloads up to about 5 GB, takes 10 to 30 minutes, and
   Windows asks once "Do you want to allow this app to make changes to your
   device?": answer Yes.
   (To install them by hand instead: Visual Studio 2022 from
   https://visualstudio.microsoft.com/downloads/ with the workload "Desktop
   development with C++" and the components "C++ Clang Compiler for Windows"
   and "C++ CMake tools for Windows"; Python 3.10 or newer from
   https://www.python.org/downloads/ with "Add python.exe to PATH" ticked.)

4. About 10 GB of free disk space where you extract this kit (plus about
   8 GB on C: if Setup installs the tools), and an internet connection.

5. Windows 10 or 11, 64-bit.


INSTALL
-------
1. Extract this whole zip to a folder you like (e.g. C:\Games\CivRevPC).
2. Double-click Setup.bat. It asks for your .iso (or disc folder) and your
   EBOOT.elf, then copies the disc, generates and compiles the game.
   On a fast PC this takes about 10 minutes; slower PCs take longer.
   While it works you see one progress line per step, for example
   "Compiling: 120 of 450 files (26%)". Leave the window open until it says
   DONE. (setup.log gets everything the compilers print, including thousands
   of "warning" lines: those are normal and harmless.)
3. At the end it offers a desktop shortcut and asks whether to delete the
   build leftovers (about 1.1 GB; the game works either way).

If something goes wrong Setup stops, says why, and keeps a full log in
setup.log in the kit folder. Fix the problem and run Setup.bat again:
finished steps are skipped.


PLAY
----
Start civrev-port\CivRev.exe (or the desktop shortcut).

Keyboard          PS3 button
  Arrow keys        D-pad
  Z / X             Cross / Circle
  A / S             Square / Triangle
  Q / W             L1 / R1
  Enter / Tab       START / SELECT
An Xbox-compatible controller also works.
Alt+Enter switches fullscreen. Esc closes the game.

Your saves:     civrev-port\gamedata\   (back this folder up, never delete it)
Settings:       civrev-port\CivRev.ini  (made on first start; edit with Notepad)
                  [game]  vibration=on|off
                  [debug] auto_capture=on|off
Controller vibration, step by step: see
  "Controller vibration - how to turn it on or off.txt" in the kit folder.
Logs:           civrev-port\run.err.log (the last 10 runs are kept in civrev-port\logs\)
If the game crashes, the launcher shows a message; please include run.err.log
when you report a problem.


DEBUG KEYS (for bug reports)
----------------------------
These developer tools are part of the game program. You never need them to play.
  F9   Saves a capture of the next frame (all draw calls and textures) to
       civrev-port\build\captures\capNN\. About 1 GB each; safe to delete.
  F11  Writes a snapshot of what every game thread is doing into
       civrev-port\run.err.log. Useful when the game freezes.
  Automatic capture: the game can also capture a frame by itself when the
       screen goes black (up to 2 per session, ~1 GB each). This is OFF.
       To turn it on for a bug report, set auto_capture=on in CivRev.ini.


LEGAL
-----
You need your own, legally obtained copy of the game. This kit includes no
game data. The port's own files are under the MIT License (civrev-port\LICENSE);
civrev-port\src\compat\ comes from sp00nznet/tornado (MIT, see LICENSE-tornado).
The ps3recomp runtime that Setup downloads is MIT licensed (see its LICENSE).
