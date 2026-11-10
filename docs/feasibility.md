# Feasibility — Civilization Revolution (BLES00238)

Analysed 2026-11-10 against ps3recomp `de4f090` (v0.19.0).
Produced by `tools/relift.ps1` (loader outputs in `analysis/`, git-ignored) and
`tools/import_coverage.py` (imports vs. ps3recomp handlers).

## Verdict: realistic target, moderate difficulty
89% of the game's system calls already exist in ps3recomp. Most of the gaps are
trivial (debug printing, microphone, online). The real work is concentrated in
**SPURS** (PhysX physics runs as SPU tasks) and **cellResc** (the display
scaler). The game plays its videos with **Bink**, which decodes in the game's own
code, so it does **not** depend on ps3recomp's partial video and audio codec modules
(cellVdec, cellAdec, cellDmux, cellAtrac).

## The executable
- Decrypted `EBOOT.elf`: 26,762,152 bytes, ELF64 big-endian, OSABI 0x66 (CELL LV2), EXEC.
- Entry OPD `0x18a5a80` → code `0x14700`, TOC `0x1929e20`. Module TOC `0x1939d98`.
- **63,606 functions.** That's a large codebase, so lifting and compiling will be slow (expect long build times).
- 2 load segments: code `0x10000` (24 MB) and data `0x1860000` (1.1 MB file, 3.4 MB in memory).
- No `.sprx` modules on disc. Everything is in the EBOOT.

## Engine and middleware (from strings in the binary)
| Component | Evidence | What it means for the port |
|---|---|---|
| **Gamebryo** (Emergent) | `Gamebryo KFM File Version`, `GB_SPURS` | 3D engine. Draws through cellGcm/RSX. Graphics bugs will be Gamebryo shader and state issues. |
| **NVIDIA PhysX** on SPU | SPU images 2 and 8: `PhysX: Error writing to SPURS queue`, build tag `nx_release_2145` | Physics runs as SPURS tasks with SPURS queues. **This is the hardest part.** |
| **Bink** video | `DawnOfMan.bik`, `Bink Audio Thread`, `Bink texture format` | Intro and wonder movies are decoded by the game itself (CPU/SPU). |
| Speex | `Speex`, `sub-band CELP` | Voice chat codec. Can be skipped (no microphone). |
| Firaxis "CivConsole" | SPU image 0: `C:/projects/main/CivConsole/Src/`, `CIV_REVSPURS` | The game's own SPURS setup and jobs. |
| Asset archives | `*.FPK` (`Pregame.FPK`, `ps3_misc.FPK`, …) | Read via sys_fs, which is fully implemented. |

## SPU programs: 9 images, 913,464 bytes
| # | Offset | Size | Identified as |
|---|---|---|---|
| 0 | 0x01764A80 | 3,700 | Firaxis CivConsole SPU stub (libspurs, libdma; CELL SDK 4.1.2.7) |
| 1 | 0x01765900 | 40,872 | unknown (stripped) |
| 2 | 0x0176F900 | 34,508 | PhysX SPURS task |
| 3 | 0x01778000 | 165,844 | unknown (stripped) |
| 4 | 0x017A0800 | 38,708 | unknown (stripped) |
| 5 | 0x017A9F80 | 324,996 | Uses CellStackAllocator. Likely a PhysX solver or Gamebryo SPU job. |
| 6 | 0x017F9580 | 139,720 | unknown (stripped) |
| 7 | 0x0181B780 | 144,344 | unknown (stripped) |
| 8 | 0x0183EB80 | 20,772 | PhysX SPURS task (nx_release_2145, CELL SDK 4.1.3.0) |

## Firmware imports: 223 from 16 libraries
198 implemented, 5 trivial stubs, **20 missing**.
"Implemented" means a handler exists under that NID. It does **not** prove the
handler behaves correctly for this game.

| Library | Imports | Impl. | Stub | Missing |
|---|---|---|---|---|
| cellSpurs | 30 | 26 | 0 | 4 |
| sysPrxForUser | 28 | 26 | 0 | 2 |
| sceNp | 27 | 25 | 0 | 2 |
| sys_net | 21 | 19 | 1 | 1 |
| sys_fs | 20 | 20 | 0 | 0 |
| cellGcmSys | 18 | 17 | 0 | 1 |
| cellSysutil | 17 | 17 | 0 | 0 |
| cellResc | 15 | 12 | 0 | 3 |
| cellMic | 15 | 8 | 2 | 5 |
| cellAudio | 10 | 9 | 0 | 1 |
| cellNetCtl | 6 | 6 | 0 | 0 |
| sys_io | 6 | 6 | 0 | 0 |
| cellSysmodule | 4 | 2 | 2 | 0 |
| cellRtc | 3 | 3 | 0 | 0 |
| cellOvis | 2 | 1 | 0 | 1 |
| cellUserInfo | 1 | 1 | 0 | 0 |

### Missing functions, by priority
**Must implement (affect boot, graphics or game logic):**
- `cellSpurs`: `cellSpursQueuePopBody` (0x91066667), `cellSpursQueueDetachLv2EventQueue` (0x039D70B7),
  `cellSpursTaskExitCodeGet` (0x13AE18F3), `cellSpursTaskAttributeSetExitCodeContainer` (0xA121A224).
  The queue functions are probably the PPU side of PhysX's SPURS queues.
- `cellResc`: `cellRescSetWaitFlip` (0x0D3C22CE), `cellRescGcmSurface2RescSrc` (0x01220224),
  `cellRescVideoOutResolutionId2RescBufferMode` (0xD1CA0503). These belong to the display output scaler.
- `cellGcmSys`: `_cellGcmFunc15` (0x3A33C1FD). This is an internal GCM helper.
- `cellOvis`: `cellOvisInitializeOverlayTable` (0xA876C911). It sets up SPU overlays and needs investigating.

**Easy (a small handler that just succeeds or does something trivial):**
- `cellAudio`: `cellAudioSetPortLevel` (0x56DFE179). Sets volume.
- `sysPrxForUser`: `_sys_spu_printf_initialize` / `_sys_spu_printf_finalize`. SPU debug printing.

**Can stay offline or no-device:**
- `cellMic`: 5 unnamed NIDs (0x05709BBF, 0x65336418, 0x6BC46AAB, 0x7903400E, 0xB2C16321).
  `cellMicClose` and `cellMicStop` are stubs. Voice chat only.
- `sceNp`: `sceNpLookupNpIdAsync`, `sceNpBasicGetBlockListEntry`. Online only.
- `sys_net`: 1 unnamed NID (0xF7AC8941). `sys_net_abort_resolver` is a stub. Online only.

## Caveats
- The coverage script matches handlers by name patterns and NIDs. Its first
  version wrongly reported 8 sys_net functions as missing, because they're
  registered through a name table in `libs/network/sysNet.c`. The remaining "missing"
  entries were spot-checked with grep and are genuinely absent.
- cellSpurs is listed as **Partial** in `docs/MODULE_STATUS.md`. Even "implemented"
  SPURS functions may misbehave under PhysX.
- `tools/triage_elf.py` crashes on a Windows path with no parent folder
  (`IndexError` at line 48). Pass a path with forward slashes, or skip that tool.
