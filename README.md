# civrev-port: Civilization Revolution (PS3) → native PC

`BLES00238`, European disc release (Firaxis / 2K Games, 2008). Statically recompiled
with [ps3recomp](https://github.com/sp00nznet/ps3recomp). The project layout follows
[sp00nznet/tornado](https://github.com/sp00nznet/tornado).

**Status:** boots through C runtime start-up, opens the D3D12 window and reads the
disc archives, runs PhysX on the SPU task system and reaches the animated "Press
START" title screen with clean music. Input and gameplay are untested.
See [docs/progress.md](docs/progress.md) and [docs/feasibility.md](docs/feasibility.md).

## Requirements
- Windows, Visual Studio 2022 with *C++ Clang Compiler for Windows* and *C++ CMake tools for Windows*.
- A [ps3recomp](https://github.com/sp00nznet/ps3recomp) checkout with its Python `.venv`
  set up and `build-release\ps3recomp_runtime.lib` built (Release, clang-cl).
- **Your own** copy of the game. Decrypt `PS3_GAME\USRDIR\EBOOT.BIN` to `EBOOT.elf`
  with RPCS3 (*Utilities → Decrypt PS3 Binaries*).

## Folder layout
The scripts look for these folders side by side by default:
```
ps3recomp\          ps3recomp checkout
civrev-gamefiles\   your game files; keep them outside every repo
  EBOOT.elf           decrypted game program
  vfs\PS3_GAME\       the disc's PS3_GAME folder, copied as-is (the game's "/dev_bdvd")
civrev-port\        this repository
```
Other locations: `tools\relift.ps1 -PS3Recomp <path> -Elf <path>`, and
`-DPS3RECOMP_DIR=<path>` (or the `PS3RECOMP_DIR` environment variable) for CMake.

## Build
```powershell
powershell -ExecutionPolicy Bypass -File tools\relift.ps1   # generate code from your EBOOT.elf (~2 min)
powershell -ExecutionPolicy Bypass -File build.ps1          # compile build\civrev.exe (~5 min, 16 threads)
```

## Run
Double-click `run.bat`. It sets `PS3_VFS_ROOT` to `..\civrev-gamefiles\vfs`, starts
`build\civrev.exe ..\civrev-gamefiles\EBOOT.elf` and writes the output to `run.log` and
`run.err.log`. Started without arguments, `civrev.exe` only prints its usage and exits.

## Repository contents
| Path | What |
|---|---|
| `CMakeLists.txt`, `build.ps1` | Build configuration (clang-cl + Ninja) |
| `run.bat` | Starts the game with the folder layout above |
| `tools/fix_import_stub_toc.py` | Post-lift fix: import stubs save r2 like the real PS3 stub (run by `relift.ps1`) |
| `tools/fix_inline_opd_funcs.py` | Pre-lift fix: adds 108 hand-written routines reached only via inline descriptors (run by `relift.ps1`) |
| `src/port/civrev_hle.cpp` | Civ Rev-specific HLE overrides (`cellOvisGetOverlayTableSize`, `_cellSpursQueuePopBody`) |
| `tools/relift.ps1` | Runs the ps3recomp pipeline on your EBOOT: loader, PPU lifter, HLE table, SPU lifter |
| `tools/import_coverage.py` | Checks the game's firmware imports against ps3recomp's handlers |
| `src/compat/` | POSIX header shims for Windows |
| `docs/` | Progress log and feasibility analysis |

## Legal
This repository contains no game code, assets or keys, only build configuration,
scripts and notes. Everything generated from the game is git-ignored. You need
your own legally obtained copy of the game.

This project's own files are under the MIT License (see [LICENSE](LICENSE)).
`src/compat/` is from sp00nznet/tornado, MIT License, © 2026 Ned Heller / sp00nznet
(see [src/compat/LICENSE-tornado](src/compat/LICENSE-tornado)).
