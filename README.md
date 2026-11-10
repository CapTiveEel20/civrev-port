# civrev-port: Civilization Revolution (PS3) → native PC

`BLES00238`, European disc release (Firaxis / 2K Games, 2008). Statically recompiled
with [ps3recomp](https://github.com/sp00nznet/ps3recomp). The project layout follows
[sp00nznet/tornado](https://github.com/sp00nznet/tornado).

**Status:** `civrev.exe` compiles and links (0 errors). It has not been booted yet.
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
civrev-gamefiles\   EBOOT.elf (your game files; keep them outside every repo)
civrev-port\        this repository
```
Other locations: `tools\relift.ps1 -PS3Recomp <path> -Elf <path>`, and
`-DPS3RECOMP_DIR=<path>` (or the `PS3RECOMP_DIR` environment variable) for CMake.

## Build
```powershell
powershell -ExecutionPolicy Bypass -File tools\relift.ps1   # generate code from your EBOOT.elf (~2 min)
powershell -ExecutionPolicy Bypass -File build.ps1          # compile build\civrev.exe (~5 min, 16 threads)
```

## Repository contents
| Path | What |
|---|---|
| `CMakeLists.txt`, `build.ps1` | Build configuration (clang-cl + Ninja) |
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
