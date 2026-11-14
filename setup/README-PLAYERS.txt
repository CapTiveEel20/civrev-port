Sid Meier's Civilization Revolution (PS3) - PC build kit
=========================================================

This kit turns YOUR OWN copy of the PS3 game into a native Windows program.
It contains no game code, art or keys: everything game-specific is made on
your PC from your disc. Only the European disc BLES00238 is supported.

WHICH GAME VERSION THIS KIT BUILDS
There are two kits; the zip name tells you which one you have:
  CivRevPC-<kit version>-game1.0.zip    game version 1.0: the game as it is
                                        on the disc. You need only your disc.
  CivRevPC-<kit version>-game1.30.zip   game version 1.30: the game's official
                                        update. You need your disc AND the
                                        1.30 update package.
(It is also written in civrev-port\setup\game-version.txt.)


WHAT YOU NEED
-------------
1. Your game disc as an .iso file, or the extracted disc folder
   (the folder that contains PS3_GAME and PS3_DISC.SFB).

2. The decrypted game program, EBOOT.elf, made with the RPCS3 emulator
   (https://rpcs3.net).

   GAME VERSION 1.0 (from the disc):
     a. Copy the disc's PS3_GAME\USRDIR\EBOOT.BIN to an ordinary folder.
     b. RPCS3: Utilities > Decrypt PS3 Binaries, choose that EBOOT.BIN.
     c. RPCS3 writes EBOOT.elf next to it: give that file to Setup.

   GAME VERSION 1.30 (from the update):
     a. RPCS3: File > Install Packages/Raps/Edats, choose the game's 1.30
        update package (a .pkg file). RPCS3 installs it in its own folder.
     b. RPCS3: Utilities > Decrypt PS3 Binaries, choose the update's
        EBOOT.BIN RIGHT WHERE RPCS3 INSTALLED IT (do not copy it first):
          <RPCS3 folder>\dev_hdd0\game\BLES00238\USRDIR\EBOOT.BIN
        (about 37 MB; the disc's is about 27 MB).
     c. RPCS3 writes EBOOT.elf next to it: give that file to Setup.
     Why there: the update is the new program PLUS 23 new files (menus,
     translated text, models) that the game needs. Setup picks them up by
     itself from next to your EBOOT.elf (it also checks your RPCS3 folder).

   Setup refuses the still-encrypted EBOOT.BIN, and an EBOOT.elf of the
   other game version (it tells you which kit that one needs).

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


UPDATING FROM AN OLDER KIT (for example kit 1.1 -> 1.2)
-------------------------------------------------------
1. Extract the new zip to the same place as before, so its CivRevPC folder
   lands on top of your existing one ("Replace the files in the
   destination").
2. Run Setup.bat again. If the new kit uses a newer ps3recomp runtime, Setup
   downloads it and rebuilds the game (about as long as the compile step
   took the first time); otherwise it has nothing to redo. Your disc copy is
   kept.
3. Your saves in civrev-port\gamedata\ are kept.
Use the newer kit for the SAME game version you have (kits 1.0 and 1.1
built game version 1.0).


SWITCHING BETWEEN GAME VERSION 1.0 AND 1.30
-------------------------------------------
1. Back up civrev-port\gamedata\ first (saves of one game version have not
   been tested with the other).
2. Extract the kit for the other game version on top of your CivRevPC folder
   (as above) and run Setup.bat. It notices the change, asks for the
   matching EBOOT.elf (see WHAT YOU NEED, point 2) and rebuilds the game. The disc copy is kept. Going back to 1.0 removes the
   update's files from the game folder.
Or keep both: extract the two kits into two different folders and run
Setup.bat in each (about 10 GB each; each has its own saves).


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
