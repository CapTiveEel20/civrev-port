# Progress log

Newest first. Each entry: what we saw (symptom) → why (cause) → what fixed it.
Fixes in ps3recomp itself are marked **[runtime]**.

## 2026-11-10: title screen runs, music plays cleanly

- Symptom (seen by eye): "Press START" screen with music, but the clouds froze after
  about a second and the music stuttered. `AUDIO_RATE=1`: host output fine (0
  underruns), but the game's sound engine (Miles, a PPU thread) left 3-23 holes per 5 s.
  816 s of CPU in 60 s: 16 cores busy with 165 threads.
- Cause: PhysX starts one SPURS task per job; each task pushes a 16-byte result into
  an SPU->PPU queue (`0x01B72880`, depth 128) and exits. The PPU collects results with
  `_cellSpursQueuePopBody` (NID `0x91066667`), which ps3recomp doesn't implement, so
  it returned 0 ("got one") without removing anything. After 128 results the queue was
  full (`[spu-spin] ... GETLLAR ea=0x01B72880 line: 00000000 00000080 00000000 00000080`
  = read 0, write 128, depth 128). Every later task spun forever on its push (256
  started, 128 finished), PhysX ran out of task slots (`Error starting spurs task
  0x80410904`), the game called `sys_prx_exitspawn_with_level` and its loop stopped.
- Fix: `src/port/civrev_hle.cpp` implements the pop on ps3recomp's queue ring model
  (`+0x00` read index, `+0x04` write index, `+0x0C` depth, `+0x10` entry size, `+0x18`
  buffer; indices mod 2*depth). Under `spu_lockline_lock` it must touch guest memory
  directly: `vm_write*` takes that (non-recursive) lock itself on a line an SPU has
  reserved, and the first version deadlocked the game that way.
- Result (60 s): 3,065 tasks started / 3,064 finished, 0 spinning, 71 s CPU (~1.2
  cores), 37 threads, audio holes 0 and 0 % silence, no PhysX error, clouds keep moving
  (screenshots 3 s apart: 99.6 % of the sky changed).
- Open: the popped entries read as all zeros; PhysX accepts them, but it is not yet
  confirmed that the SPU side writes its results into the slot this ring model reads.

## 2026-11-10: PhysX gets past SPURS program loading

- `PhysX: Error allocating memory for overlay table: 0 0`. PhysX calls
  `cellOvisGetOverlayTableSize(spuElf)` (guest `0x00FED62C`) and reads the size
  from the return value. ps3recomp's stub (`libs/misc/cellOvis.c`) has a different
  signature, `(filePath, u32* tableSize)`, and needs a `cellOvisInit` the game never
  calls, so it returns `0x80410701`. PhysX reads that as a ~2 GB size and the
  allocation fails. Trace: `PS3_HLE_ARGS=82F294B2` → `r3=0x0184EB80` (an SPU ELF),
  `r4=0`. None of the 9 SPU images has an `.ovtab` section, so the right answer is 0.
  Fix: `src/port/civrev_hle.cpp` registers a ctx handler for NID `0x82F294B2`
  (ctx handlers are dispatched before the generic table) that returns 0 and warns
  if an ELF ever does have overlays.
- Next: `[ppu] FATAL: stuck calling 0x00FC2EA8`. 108 hand-written routines
  (`0x00FBABE0`-`0x00FC41A8`, likely PhysX) are reached only through **inline**
  function descriptors `{code=desc+8, toc=0}` inside `.text`. The loader builds its
  function list from `.opd`, so it merged all of them into `0x00FB94F0` and the
  lifter never emitted them. Fix: `tools/fix_inline_opd_funcs.py` (run by
  `relift.ps1` step 1) splits them out: 63,606 → 63,714 entries, 80,330 → 80,495
  lifted functions.
- Now runs > 60 s. PhysX creates SPURS queues and tasks, then stops with
  `PhysX: Error starting spurs task: 0x80410904` (`CELL_SPURS_TASK_ERROR_NOMEM`)
  after creating 256 tasks for the same SPU program. Also unimplemented:
  `cellSpursQueuePopBody` (`0x91066667`, 35 calls), `inet_addr`, `_sys_spu_printf_initialize`.

## 2026-11-10: first readable screen ("Caricamento...")

- With the default D3D12 backend the window shows one line of text at the bottom,
  upside down and mirrored. Flipped vertically it reads "Qa fpamNdne": the glyphs
  are upright but they're the wrong characters. That backend's viewport epilogue
  keeps x/y as identity (`rsx_d3d12_backend.c`, "x/y identity"), so it ignores the
  sign of the guest's viewport Y scale. This game also picks the wrong glyphs from
  its font atlas there.
- With `RSX_LIVE_DRAW=1` (ps3recomp's live-draw engine, which honours
  SET_SHADER_WINDOW) the same frame reads **"Caricamento..."** (Italian, following
  the host language), the right way up and centred at the top. `run.bat` now sets it.
- The game stays on that screen: PhysX/SPURS failure (see below).

## 2026-11-10: disc data in place, next blocker is PhysX/SPURS

- Disc `PS3_GAME` copied to `civrev-gamefiles\vfs\` (83 files, 4.92 GB). `run.bat`
  sets `PS3_VFS_ROOT` to it. Title id `BLES00238` read from PARAM.SFO. The `.FPK`
  archives open and read.
- 283 distinct paths fail to open: loose shaders (`Shaders/PS3/*.NSB`, `GBCache/`,
  `USRDIR/*.vpo|*.fpo`). The disc's `Shaders` folders are empty, so the game probes
  for loose files and falls back to the archives. Not a port bug.
- One unresolved import: NID `0x45FE2FCE`.
- Stops here: `PhysX: Error allocating memory for overlay table` → `Cannot load SPURS
  programs` → `Cannot run without SPURS`, then `sys_prx_exitspawn_with_level` and a
  `cellGcmSetFlipMode` loop.
- **[runtime]** The fast-path TOC bug is fixed upstream by open PR
  [sp00nznet/ps3recomp#760](https://github.com/sp00nznet/ps3recomp/pull/760). Its exact
  `ppu_hle.cpp` boots Civ Rev without our stub fix: 0 null reads, 40 s, 5 FPKs open.
  Keep `fix_import_stub_toc.py` until #760 is merged.

## 2026-11-10: first boot, past the C runtime start-up

- Run: `build\civrev.exe <EBOOT.elf>`. With no argument it prints usage and exits
  (code 2). Double-clicking it shows nothing for that reason.
- Symptom: null reads at `NULL+0x47B4` in `func_013D1870` right after start-up,
  then an infinite recursion and a stack overflow.
- Cause: r2 (TOC) became 0 inside `func_013D2A90` (a run-once helper). Its first
  import call in a fresh frame is `sys_lwmutex_lock`. ps3recomp registers that
  import (and `sys_lwmutex_unlock`) as a "fast" HLE call, which returns before
  writing the caller's TOC slot `0x28(r1)`. The caller then reloads `r2 = [r1+0x28]`
  = 0. Proven with temporary r2 prints at each restore point.
- Fix: `tools/fix_import_stub_toc.py` (run by `relift.ps1`) makes each lifted import
  stub do `std r2,40(r1)` first, like the real PS3 stub. 223 stubs.
  Candidate upstream fix: write the slot in ps3_hle_call's fast path too.
- Result: no null reads, no crash. The D3D12 window opens and the game runs until
  it tries to open `/dev_bdvd/PS3_GAME/USRDIR/Resource/*.FPK`, which fails because
  the disc isn't extracted yet.

## 2026-11-10: first full build, civrev.exe links

`build.ps1 -- -k 0`: **0 errors, 4.2 min** (16 threads), `build\civrev.exe` = 243.5 MB.
There are 1,449 warnings, all cosmetic: 1,065 `-Wparentheses-equality` (lifted code style),
257 `-Wdeprecated-declarations` (CRT functions), 126 `-Wunused-value` (`_mul128`
in the lifter preamble) and 1 `-Wdeprecated-volatile`.

Not run yet. The first boot needs the disc files as a VFS root (`PS3_VFS_ROOT`) and
the env switches Tornado uses (`RSX_LIVE_DRAW=1`, `PS3_MAIN_STACK_LV2=1`).

## 2026-11-10: first lift

`tools\relift.ps1` ran the whole pipeline in about 100 s:

| Stage | Result |
|---|---|
| Lift time | 76 s with 16 workers |
| Functions lifted | **80,330** (63,606 OPD + call targets; 11,262 merged functions split by prologue scan) |
| Jump tables | 868 dispatchers, 9,448 cases |
| Import stubs | 223 → `ps3_hle_call` |
| TOC candidates | `0x1929e20`, `0x1939d98`, `0x1949d58` (multi-TOC binary) |
| Output | 64 chunks + table, **12.99 M lines, 774 MB** |
| HLE table | 1,238 handlers from 93 modules |
| SPU | 9/9 images lifted. "Unsupported" instructions are all `.word` (data in .text). |

| Symptom | Cause |
|---|---|
| Chunk 000 had 177k lines, only 45 functions, and compiled in 2 s to 36 KB | The linker's **TOC-switch stubs** (`std r2,40(r1); addis r2,r2,±1; addi r2,r2,N; b target`, 16 bytes each) aren't in the OPD. Each stub lifts as a "function" running to the next known start, so every stub carries a dead copy of all stubs after it. 1.75 M dead stub copies ≈ 7 M of the 13 M lines, in 25 chunks. It's correct (each returns at its first `b`), and the compiler drops the dead code. **TODO:** give the lifter 16-byte stub boundaries. |
| `clang-cl: unknown argument ignored: '-ffp-contract=off'` | clang-cl needs `/clang:-ffp-contract=off`. Without it, FMA contraction is allowed and float results drift from the PS3. Fixed in CMakeLists. **Tornado's CMakeLists has the same bug.** |

Densest chunk (`ppu_recomp_049.cpp`, 5,570 functions): 52 s and < 1 GB RAM at -O2.

## 2026-11-10: project created

- Layout copied from sp00nznet/tornado. Uses `runtime/ppu/tests/boot_main.cpp` as
  the boot harness and links `ps3recomp_runtime.lib` (Release).
- Game facts:
  - EBOOT: 63,606 functions, 223 imports across 16 libraries, 9 SPU images (913 KB).
  - `--code-end 0x01416CEC`, the end of the 223 import stubs.
  - Middleware: Gamebryo, PhysX on SPURS, Bink, Speex.
- Import coverage against ps3recomp v0.19.0: 198 implemented, 5 stubs, 20 missing.
  The detailed list is in [feasibility.md](feasibility.md).
