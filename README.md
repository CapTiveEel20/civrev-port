# Civilization Revolution: PC port

Play **Sid Meier's Civilization Revolution** (PS3, 2008) on Windows as a normal PC
program, made **from your own copy of the game**. It is not an emulator: the
game's PS3 program is translated into PC code, on your computer, during setup.

> ### ⚠️ Please read first: this download does NOT contain the game
> - The download (and this whole repository) contains **no game code, no graphics,
>   no sounds, no music, no videos and no keys**. It is about 40 KB of scripts and
>   this project's own source code.
> - **You need your own copy** of the PS3 game: the **European disc, BLES00238**.
>   Other versions (for example the North American BLUS30130) do not work.
> - Everything that comes from the game is made **on your PC, from your copy**, while
>   Setup runs. Nothing from the game is ever downloaded from here.
> - This is a fan project. It is not affiliated with or endorsed by Firaxis Games,
>   2K, Take-Two Interactive or Sony.

> ### ℹ️ Choose your game version: 1.0 or 1.30
> The port supports two versions of the game. Each has its own download, and you
> pick one (see [Which version should I choose?](#which-version-should-i-choose)):
> - **Game version 1.0**: the program that is on the disc itself, with no updates.
>   Download **`CivRevPC-<version>-game1.0.zip`**. You only need your disc.
> - **Game version 1.30**: the game's official update. Download
>   **`CivRevPC-<version>-game1.30.zip`**. You need your disc **and** the 1.30
>   update package, installed in RPCS3 (see [Step 1c](#1c-only-for-game-version-130-the-game-update)).

## What works today
- **The whole game, start to finish:** full matches play without problems,
  including long ones.
- **High frame rate:** on the developer's PC (AMD Ryzen 7 9850X3D, NVIDIA
  GeForce RTX 4060 Ti) the game usually runs **well above 60 FPS, typically
  70 to 180 FPS**.
- **Saving:** the game's own menus to **save, load and delete** games work.
  Saves are kept in a folder you can back up.
- **Playtime counter:** the game window's title bar shows your **total
  playtime** and the time of the **current session**.
- **Controllers:** Xbox-compatible controllers work directly; PlayStation
  controllers work through a tool that makes them look like an Xbox controller
  (for example DS4Windows, or Steam).
- **Videos, music and sound** from your disc, controller vibration (can be
  switched off), fullscreen (Alt+Enter).

---

## Contact
Questions, problems or ideas? You can reach me in two ways:
- **GitHub:** open an [issue](https://github.com/CapTiveEel20/civrev-port/issues).
  This is the best place for bug reports: attach `setup.log` (Setup problems) or
  `civrev-port\run.err.log` (game problems).
- **Discord:** my username is **captiveeel20**. Send me a friend request or a
  message.

Please don't send or ask for game files, `EBOOT` files or ISOs: I can't share them.

---

## Contents
1. [How it works (in 30 seconds)](#how-it-works-in-30-seconds)
2. [What you need](#what-you-need)
3. [Step 1: prepare your game files](#step-1-prepare-your-game-files)
4. [Step 2: install](#step-2-install)
5. [Playing](#playing)
6. [Known problems](#known-problems)
7. [Help and common questions](#help-and-common-questions)
8. [Uninstalling](#uninstalling)
9. [For developers](#for-developers)
10. [Legal and credits](#legal-and-credits)

---

## How it works (in 30 seconds)
1. You download a small zip (about 40 KB) from [Releases](https://github.com/CapTiveEel20/civrev-port/releases):
   the one for game version **1.0** or the one for game version **1.30**.
2. You run **Setup.bat** and give it files from **your** game: the disc (`.iso`)
   and the decrypted game program (`EBOOT.elf`). For version 1.30 also the
   installed game update.
3. Setup copies your disc, translates the game program into PC code and builds
   the game. **About 10 minutes on a fast PC**, longer on slower ones (plus
   10 to 30 minutes the first time, if it has to install the free build tools).
4. You play from the desktop shortcut.

---

## What you need

| What | Details |
|---|---|
| **Your game** | Sid Meier's Civilization Revolution for PS3, **European disc BLES00238**, as a decrypted `.iso` file or as the disc folder (see Step 1). |
| **The decrypted game program** | `EBOOT.elf`, made with the free RPCS3 emulator (see Step 1). **Game version 1.0:** from the disc's own program. **Game version 1.30:** from the update's program. |
| **Only for game version 1.30: the game update** | The official **1.30 update package** (`.pkg`) for BLES00238, installed in RPCS3 (see Step 1c). |
| **Windows** | Windows 10 or 11, 64-bit (tested on Windows 11). |
| **Graphics card** | One that supports DirectX 12. |
| **Processor** | Any 64-bit processor with SSE4.1 (practically every PC processor since about 2011). |
| **Disk space** | About **10 GB** free where you put the game, plus about **8 GB on C:** if Setup has to install the build tools. |
| **Internet** | Only during Setup. |
| **Build tools** | Visual Studio 2022 Build Tools (Microsoft's free C++ compiler) and Python. **You don't need to install them yourself:** if they are missing, Setup offers to install them for you. |
| **Controller** | An Xbox-compatible controller, or a PlayStation controller through DS4Windows or Steam. |

---

## Step 1: prepare your game files

You need two things from **your own** game disc (1a and 1b). For game version
1.30 you also need the game update (1c), and you make the `EBOOT.elf` from the
update instead of from the disc.

### 1a. Your disc as an `.iso` or a folder
- **Either** a decrypted `.iso` file of your disc: if you double-click it,
  Windows opens it and you see a `PS3_GAME` folder,
- **or** the disc folder: the folder that contains `PS3_GAME` and `PS3_DISC.SFB`
  (the "folder" format RPCS3 uses).

To make one from your disc, see RPCS3's guide: <https://rpcs3.net/quickstart>.

### 1b. The decrypted game program (`EBOOT.elf`)
The game program on the disc (`EBOOT.BIN`) is encrypted. RPCS3, a free PS3
emulator, can decrypt it. You only need RPCS3 for this one step.

1. Download and install RPCS3: <https://rpcs3.net/download>. If RPCS3 asks you
   to install the PS3 firmware first, follow its instructions.
2. Copy the right `EBOOT.BIN` to an ordinary folder, for example a new folder
   on your Desktop:
   - **Game version 1.0:** the one on your disc, inside `PS3_GAME\USRDIR\`
     (with an `.iso`, double-click it first to open it).
   - **Game version 1.30:** the one from the update, after Step 1c:
     `dev_hdd0\game\BLES00238\USRDIR\EBOOT.BIN` inside your RPCS3 folder.
     It is bigger (about 37 MB; the disc's is about 27 MB).
3. In RPCS3: **Utilities → Decrypt PS3 Binaries**, then choose that `EBOOT.BIN`.
4. RPCS3 writes **`EBOOT.elf`** next to it. That's the file Setup needs.

Setup checks this file. It tells you if it is still encrypted, or if it
belongs to a different game version than the kit you downloaded.

### 1c. Only for game version 1.30: the game update
1. In RPCS3: **File → Install Packages/Raps/Edats**, then choose the 1.30
   update package of the game (for BLES00238, a `.pkg` file).
2. RPCS3 installs it into `dev_hdd0\game\BLES00238\` inside your RPCS3 folder.
   Setup asks for that folder. It copies the update's own files from it (about 7 MB)
   and checks that it really is the complete 1.30 update.
3. Now make the `EBOOT.elf` from the update's `EBOOT.BIN` (Step 1b).

---

## Step 2: install
1. Go to [Releases](https://github.com/CapTiveEel20/civrev-port/releases) and,
   under "Assets", download the zip for **your game version**:
   - game version 1.0: **`CivRevPC-<version>-game1.0.zip`** (for example `CivRevPC-1.2-game1.0.zip`)
   - game version 1.30: **`CivRevPC-<version>-game1.30.zip`** (for example `CivRevPC-1.2-game1.30.zip`)

   (Two different numbers: `1.2` is the version of this kit, `game1.0` or
   `game1.30` is the version of the game it builds.)
2. Right-click the zip → **Extract All…** and choose a folder with enough free
   space, for example `C:\Games`. Don't run anything from inside the zip.
3. Open the extracted `CivRevPC` folder and double-click **`Setup.bat`**.
   If Windows warns you about a downloaded file, choose **Run**
   (or **More info → Run anyway**).
4. Answer Setup's questions:
   - **"Install them now?"**: shown only if the build tools are missing.
     Answer **Y**. Windows asks once *"Do you want to allow this app to make
     changes to your device?"*: answer **Yes**. An installer window shows its
     progress.
   - **Your disc**: choose your `.iso`. To use a disc folder instead, press
     **Cancel** and then choose the folder.
   - **Only for game version 1.30, the installed update**: choose the folder
     `dev_hdd0\game\BLES00238` inside your RPCS3 folder (Step 1c).
   - **Your `EBOOT.elf`**: choose the file from Step 1b.
5. **Wait.** Setup shows one progress line per step, for example
   `Compiling: 120 of 450 files (26%)`. Leave the window open until it says
   **DONE**. The steps are:
   1. Check tools
   2. Copy your game disc (about 5 GB)
   3. *Only for game version 1.30:* Copy the game update (about 7 MB)
   4. Check your EBOOT
   5. Tidy the multiplayer menu art
   6. Download and build the ps3recomp runtime
   7. Generate code from your EBOOT (a few minutes)
   8. Compile the game (the longest step: 5 to 30+ minutes depending on your processor)
   9. Build the launcher

   (The 1.0 kit has no update step, so it shows 8 steps.)
6. At the end Setup asks two things:
   - **Create a desktop shortcut?** Yes is recommended.
   - **Delete the build leftovers (about 1.1 GB)?** The game works either way.
     Answer **No** if you want a later update to install faster.

**If something goes wrong**, Setup stops and says why in plain words. Fix the
problem and double-click `Setup.bat` again: finished steps are skipped.
Everything Setup did is written to `setup.log` in the same folder. That file
contains thousands of "warning" lines from the compiler: **those are normal
and harmless**.

### Updating from an older kit (for example kit 1.1 → 1.2)
1. Download the new kit zip and extract it **into the same
   place as before**, so its `CivRevPC` folder lands on top of your existing
   one. When Windows asks, choose **Replace the files in the destination**.
2. Double-click **`Setup.bat`** again. If the new kit uses a newer ps3recomp
   runtime, Setup downloads it and rebuilds the game (expect about as long as
   the "Compile the game" step took the first time); otherwise it has nothing
   to redo. Your disc copy is kept, so it doesn't ask for your files again.
3. **Your saves are kept** (`civrev-port\gamedata\` is not touched).

Use the newer kit **for the same game version** you already have (for example
`CivRevPC-1.2-game1.0.zip` over an install made with `CivRevPC-1.1.zip`, which
was game version 1.0). To change game version, see the next section.

### Switching between game version 1.0 and 1.30
You can change your mind later, in either direction, without starting over:
1. Back up your saves first: copy `civrev-port\gamedata\` somewhere safe.
   (Saves made with one game version have not been tested with the other.)
2. Download the kit for the **other** game version and extract it on top of
   your existing `CivRevPC` folder, as above.
3. Double-click **`Setup.bat`**. It notices the other game version and asks
   for the matching files: for 1.30 the installed update and the update's
   `EBOOT.elf`; for 1.0 the disc's `EBOOT.elf`. Then it rebuilds the game.
   Your disc copy is kept, so it doesn't copy the 5 GB again. Going back to
   1.0 removes the update's files from the game folder.

Or keep both: extract the two kits into **two different folders** and run
`Setup.bat` in each. Each folder has its own game, settings and saves (about
10 GB each). The desktop shortcut points to the last one set up.

---

## Playing
Start the game with the **Civilization Revolution** desktop shortcut, or with
`civrev-port\CivRev.exe` in the game folder.

- Play with a **controller** (see [What works today](#what-works-today)).
- **Alt+Enter** switches fullscreen. **Esc** closes the game.
- **Your saves** are in `civrev-port\gamedata\`. Back this folder up and never delete it.
- **Settings** are in `civrev-port\CivRev.ini` (created on the first start; open it
  with Notepad). For example: `vibration=on` or `vibration=off` for controller vibration.
- **Turning controller vibration off (or back on):** vibration is on by default. The
  kit includes a step-by-step guide next to `Setup.bat`:
  *Controller vibration - how to turn it on or off.txt*.

---

## Known problems
Kit 1.2 has so far been tested on one PC (the developer's). Game version 1.30
is newly supported and has had less play-testing than 1.0.
- Some 3D models are not drawn perfectly yet.
- **See-through shallow water after loading a second save:** if you load a
  saved game, then go back to the menu and load another one without closing
  the game, shallow water can turn transparent. Close and restart the game
  before loading the other save.
- Short stutters can happen the first time some effects appear (the game
  prepares them on the fly; the PS3 did this too).
- **Online multiplayer does not work:** the game's online service was shut
  down in 2014.

Found a problem? Please open an [issue](https://github.com/CapTiveEel20/civrev-port/issues)
and attach `setup.log` (Setup problems) or `civrev-port\run.err.log` (game
problems). Note: these logs contain folder paths, which can include your
Windows user name.

---

## Help and common questions

**Why doesn't the download just include the game, ready to play?**
A ready-made program would contain the game's code, which belongs to its
publisher. This way the download contains nothing from the game, and the game's
code is only ever made on your PC, from your own copy.

<a id="which-version-should-i-choose"></a>
**Which version should I choose, 1.0 or 1.30?**
Both play the whole game. **1.30** is the game's official update, so it is the
newer version of the game; you need the update package for it (Step 1c). **1.0**
is the game exactly as it is on the disc, needs nothing but the disc, and is the
version the port has been tested with the longest. If you don't have the update,
choose 1.0. You can switch later
(see [Switching between game version 1.0 and 1.30](#switching-between-game-version-10-and-130)).

**Setup says "This EBOOT is still encrypted".**
You chose `EBOOT.BIN`. Decrypt it with RPCS3 first (Step 1b) and choose the
`EBOOT.elf` it makes.

**Setup says the EBOOT "is game version 1.30, but this kit builds game version 1.0" (or the other way round).**
The `EBOOT.elf` and the kit are for different game versions. Either make the
`EBOOT.elf` from the other `EBOOT.BIN` (Step 1b: the disc's for 1.0, the update's
for 1.30), or download the kit for the game version of your `EBOOT.elf`.

**Setup says the EBOOT "is not a known version of the game".**
It comes from another release of the game (another region, for example) or the
file is damaged. Make it again from the European disc's or the 1.30 update's
`EBOOT.BIN` (Step 1b).

**Setup (1.30 kit) says the folder is "not the update 1.30", or has no PARAM.SFO.**
The update is not installed in that folder. Install the 1.30 update package
with RPCS3 (Step 1c), then choose `dev_hdd0\game\BLES00238` in your RPCS3 folder.
That folder exists before the update too: the game keeps its own data there,
but without the update's files.

**Setup says the disc is a different one (for example "BLUS30130").**
Only the European disc BLES00238 is supported.

**Setup says something is "Missing".**
It lists exactly what: build tools, free disk space, or 64-bit Windows. If you
said No to installing the tools, run `Setup.bat` again and answer Y, or install
them by hand as described in the message.

**The game crashed.**
The launcher shows a message. Please report it with `civrev-port\run.err.log`
(see [Known problems](#known-problems)).

**Can I share the game folder with a friend?**
No. After Setup, the folder contains your copy of the game and a program made
from the game's code. Point your friend to this page instead.

---

## Uninstalling
1. Copy `civrev-port\gamedata\` somewhere safe if you want to keep your saves.
2. Delete the `CivRevPC` folder and the desktop shortcut.
3. If Setup installed Visual Studio Build Tools or Python and you don't need
   them anymore, remove them in **Windows Settings → Apps**.

---

## For developers
<details>
<summary>Building without the kit, repository layout, making a kit</summary>

The game's PS3 program is statically recompiled with
[ps3recomp](https://github.com/sp00nznet/ps3recomp): its PowerPC and SPU code
is translated to C++ and linked with a runtime that stands in for the PS3's
system (graphics → Direct3D 12, audio → WASAPI, controller → XInput).
The kit uses the fork [CapTiveEel20/ps3recomp](https://github.com/CapTiveEel20/ps3recomp)
at the commit in `setup/ps3recomp.lock`. The project layout follows
[sp00nznet/tornado](https://github.com/sp00nznet/tornado).

**Requirements:** Visual Studio 2022 with *C++ Clang Compiler for Windows* and
*C++ CMake tools for Windows*; a ps3recomp checkout with its Python `.venv` and
`build-release\ps3recomp_runtime.lib` (Release, clang-cl); your decrypted `EBOOT.elf`.

**Folder layout** (side by side, by default):
```
ps3recomp\          ps3recomp checkout
civrev-gamefiles\   your game files; keep them outside every repo
  EBOOT.elf           decrypted game program (1.0 or 1.30)
  vfs\PS3_GAME\       the disc's PS3_GAME folder (the game's "/dev_bdvd")
  vfs\game\BLES00238\ game 1.30 only: the update's PARAM.SFO, PS3LOGO.DAT and
                      USRDIR\patch\ (the game's "/dev_hdd0/game/BLES00238")
civrev-port\        this repository
```
Other locations: `tools\relift.ps1 -PS3Recomp <path> -Elf <path>`, and
`-DPS3RECOMP_DIR=<path>` (or the `PS3RECOMP_DIR` environment variable) for CMake.

**Build and run:**
```powershell
powershell -ExecutionPolicy Bypass -File tools\relift.ps1   # generate code from your EBOOT.elf
powershell -ExecutionPolicy Bypass -File build.ps1          # compile build\civrev.exe
```
`run.bat` starts `build\civrev.exe` with `PS3_VFS_ROOT=..\civrev-gamefiles\vfs`
and writes `run.log` / `run.err.log`.

**Making the player kits:** `tools\make_kit.ps1 -Version <n> -GameVersion 1.0|1.30`
packs `dist\CivRevPC-<n>-game<game version>.zip` from an allowlist of files (it
refuses uncommitted changes) and adds `setup\game-version.txt`, which tells Setup
which game version to build. Both kits share all code; the EBOOT hashes and the
1.30 update's file count and size are in `setup\kitlib.ps1` (`$GameVersions`).
Tests: `setup\tests\*.tests.ps1`. Optional real-file checks: set
`CIVREV_UPDATE_DIR` (installed 1.30 update folder) and `CIVREV_EBOOT_130`
(decrypted 1.30 `EBOOT.elf`).

| Path | What |
|---|---|
| `CMakeLists.txt`, `build.ps1` | Build configuration (clang-cl + Ninja) |
| `run.bat` | Starts the game with the folder layout above |
| `setup/` | The player kit: `Setup.bat`, `setup.ps1`, `kitlib.ps1`, `README-PLAYERS.txt`, tests |
| `launcher/` | Source of `CivRev.exe`, the game launcher |
| `tools/relift.ps1` | Runs the ps3recomp pipeline on your EBOOT (loader, PPU lifter, HLE table, SPU lifter) |
| `tools/code_end.py` | Reads where the EBOOT's code ends (1.0 and 1.30 differ) for the lifter |
| `tools/fix_import_stub_toc.py`, `tools/fix_inline_opd_funcs.py` | Fixes applied during code generation |
| `tools/patch_menu_assets.py` | Tidies one image in the multiplayer menu of your disc copy |
| `tools/make_kit.ps1` | Packs the player kit |
| `tools/import_coverage.py` | Checks the game's firmware imports against ps3recomp's handlers |
| `src/port/civrev_hle.cpp` | Civ Rev-specific overrides of PS3 system functions |
| `src/compat/` | POSIX header shims for Windows |

</details>

---

## Legal and credits
- This repository and the release contain **no game code, assets, videos or keys**,
  only scripts, build configuration and this project's own code. Everything
  generated from the game is made on your PC and is never uploaded here.
- You need your own, legally obtained copy of the game. Please don't share
  what Setup creates from it (`civrev.exe`, the generated code, the copied disc).
- *Sid Meier's Civilization Revolution* is a trademark of its respective owners.
  This project is not affiliated with or endorsed by Firaxis Games, 2K,
  Take-Two Interactive or Sony Interactive Entertainment.
- This project's own files are under the MIT License ([LICENSE](LICENSE)).
- [ps3recomp](https://github.com/sp00nznet/ps3recomp), the recompiler and runtime,
  was created by Ned Heller (sp00nznet), MIT License. This port uses a fork of it.
- `src/compat/` comes from [sp00nznet/tornado](https://github.com/sp00nznet/tornado),
  MIT License, © 2026 Ned Heller / sp00nznet ([src/compat/LICENSE-tornado](src/compat/LICENSE-tornado)).
- [RPCS3](https://rpcs3.net) is only used by you, to decrypt your own `EBOOT.BIN`.
  This project is not affiliated with it.
