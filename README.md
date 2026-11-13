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
1. You download a small zip (about 40 KB) from [Releases](https://github.com/CapTiveEel20/civrev-port/releases).
2. You run **Setup.bat** and give it two files from **your** game: the disc (`.iso`)
   and the decrypted game program (`EBOOT.elf`).
3. Setup copies your disc, translates the game program into PC code and builds
   the game. **About 10 minutes on a fast PC**, longer on slower ones (plus
   10 to 30 minutes the first time, if it has to install the free build tools).
4. You play from the desktop shortcut.

---

## What you need

| What | Details |
|---|---|
| **Your game** | Sid Meier's Civilization Revolution for PS3, **European disc BLES00238**, as a decrypted `.iso` file or as the disc folder (see Step 1). |
| **The decrypted game program** | `EBOOT.elf`, made from your disc with the free RPCS3 emulator (see Step 1). Only the disc's own program, not one from a game update. |
| **Windows** | Windows 10 or 11, 64-bit (tested on Windows 11). |
| **Graphics card** | One that supports DirectX 12. |
| **Processor** | Any 64-bit processor with SSE4.1 (practically every PC processor since about 2011). |
| **Disk space** | About **10 GB** free where you put the game, plus about **8 GB on C:** if Setup has to install the build tools. |
| **Internet** | Only during Setup. |
| **Build tools** | Visual Studio 2022 Build Tools (Microsoft's free C++ compiler) and Python. **You don't need to install them yourself:** if they are missing, Setup offers to install them for you. |
| **Controller** | An Xbox-compatible controller, or a PlayStation controller through DS4Windows or Steam. |

---

## Step 1: prepare your game files

You need two things from **your own** game disc.

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
2. Copy `EBOOT.BIN` from your disc to an ordinary folder, for example your
   Desktop. It is inside `PS3_GAME\USRDIR\` (with an `.iso`, double-click it
   first to open it).
3. In RPCS3: **Utilities → Decrypt PS3 Binaries**, then choose that `EBOOT.BIN`.
4. RPCS3 writes **`EBOOT.elf`** next to it. That's the file Setup needs.

Setup checks this file. It tells you if it is still encrypted or from a different
version of the game.

---

## Step 2: install
1. Go to [Releases](https://github.com/CapTiveEel20/civrev-port/releases) and
   download **`CivRevPC-<version>.zip`** (for example `CivRevPC-1.0.zip`,
   under "Assets").
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
   - **Your `EBOOT.elf`**: choose the file from Step 1b.
5. **Wait.** Setup shows one progress line per step, for example
   `Compiling: 120 of 450 files (26%)`. Leave the window open until it says
   **DONE**. The steps are:
   1. Check tools
   2. Copy your game disc (about 5 GB)
   3. Check your EBOOT
   4. Tidy the multiplayer menu art
   5. Download and build the ps3recomp runtime
   6. Generate code from your EBOOT (a few minutes)
   7. Compile the game (the longest step: 5 to 30+ minutes depending on your processor)
   8. Build the launcher
6. At the end Setup asks two things:
   - **Create a desktop shortcut?** Yes is recommended.
   - **Delete the build leftovers (about 1.1 GB)?** The game works either way.
     Answer **No** if you want a later update to install faster.

**If something goes wrong**, Setup stops and says why in plain words. Fix the
problem and double-click `Setup.bat` again: finished steps are skipped.
Everything Setup did is written to `setup.log` in the same folder. That file
contains thousands of "warning" lines from the compiler: **those are normal
and harmless**.

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
Version 1.0 has so far been tested on one PC (the developer's).
- Some 3D models are not drawn perfectly yet.
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

**Setup says "This EBOOT is still encrypted".**
You chose `EBOOT.BIN`. Decrypt it with RPCS3 first (Step 1b) and choose the
`EBOOT.elf` it makes.

**Setup says the EBOOT is "a different version of the game".**
Use the `EBOOT.BIN` from the disc itself. The one RPCS3 keeps after installing
a game update (in its `dev_hdd0\game\` folder) is a different version.

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
Progress notes: [docs/progress.md](docs/progress.md), [docs/feasibility.md](docs/feasibility.md).

**Requirements:** Visual Studio 2022 with *C++ Clang Compiler for Windows* and
*C++ CMake tools for Windows*; a ps3recomp checkout with its Python `.venv` and
`build-release\ps3recomp_runtime.lib` (Release, clang-cl); your decrypted `EBOOT.elf`.

**Folder layout** (side by side, by default):
```
ps3recomp\          ps3recomp checkout
civrev-gamefiles\   your game files; keep them outside every repo
  EBOOT.elf           decrypted game program
  vfs\PS3_GAME\       the disc's PS3_GAME folder (the game's "/dev_bdvd")
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

**Making the player kit:** `tools\make_kit.ps1 -Version <n>` packs
`dist\CivRevPC-<n>.zip` from an allowlist of files (it refuses uncommitted
changes). Tests: `setup\tests\*.tests.ps1`.

| Path | What |
|---|---|
| `CMakeLists.txt`, `build.ps1` | Build configuration (clang-cl + Ninja) |
| `run.bat` | Starts the game with the folder layout above |
| `setup/` | The player kit: `Setup.bat`, `setup.ps1`, `kitlib.ps1`, `README-PLAYERS.txt`, tests |
| `launcher/` | Source of `CivRev.exe`, the game launcher |
| `tools/relift.ps1` | Runs the ps3recomp pipeline on your EBOOT (loader, PPU lifter, HLE table, SPU lifter) |
| `tools/fix_import_stub_toc.py`, `tools/fix_inline_opd_funcs.py` | Fixes applied during code generation |
| `tools/patch_menu_assets.py` | Tidies one image in the multiplayer menu of your disc copy |
| `tools/make_kit.ps1` | Packs the player kit |
| `tools/import_coverage.py` | Checks the game's firmware imports against ps3recomp's handlers |
| `src/port/civrev_hle.cpp` | Civ Rev-specific overrides of PS3 system functions |
| `src/compat/` | POSIX header shims for Windows |
| `docs/` | Progress log and feasibility analysis |

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
