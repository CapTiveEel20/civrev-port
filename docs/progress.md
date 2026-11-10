# Progress log

Newest first. Each entry: what we saw (symptom) → why (cause) → what fixed it.
Fixes in ps3recomp itself are marked **[runtime]**.

## 2026-11-10: first match running ("Gioca ora" → 3D world map)

- Symptom: right after the match loading screen, the game crashed (null reads in `func_00A60D20`), always just after `unresolved NID 0xA121A224` and `0x13AE18F3`.
- Cause: each frame the game starts 2 frustum-culling SPU tasks (image 1, `spu_0000_at_01764A80`) and binds a 128-byte exit-code container to each with `cellSpursTaskAttributeSetExitCodeContainer` (`0xA121A224`). Each task ends with `cellSpursTaskExit(visible_count)` (SPU func `0x3900`: the count goes in the first word of the syscall argument at LS `0x2FD0`, then syscall 0). The PPU (`func_00AA741C`) reads every count with `cellSpursTaskExitCodeGet(container, &count)` (`0x13AE18F3`) and uses it unchecked. ps3recomp had neither function and never kept a task's exit code, so the game read garbage.
- Fix (**[runtime]**, branch `fix/rsx-array-element`): the EXIT syscall records `LS[0x2FD0]` (`spu_channels.c`); when the task ends, `spu_workload.c` writes the code into the container bound by `cellSpursCreateTaskWithAttribute`, and into the Taskset2 exit array instead of 0. New `cellSpursTaskAttributeSetExitCodeContainer` and `cellSpursTaskExitCodeGet` (waits for the task) in `libs/spurs/cellSpurs.c`. `cellSpursTaskExitCodeTryGet` is left out: the game doesn't import it.
- Result: 0 unresolved NIDs, 0 null reads. Real counts every frame (`task 0 ... exited code=0x00000140 -> container 0x111E9E00`, then `0x142`, `0x13C`, ...). "Gioca ora" goes straight into a match: 3D world map, Rome, Warriors, advisor and HUD, about 27-40 FPS, still running after 60 s.

## 2026-11-10: 3D Leader Selection (Mao Zedong) & Match Loading reached; SPU `.ctors` lifted; next blocker traced to `cellSpursTaskExitCodeGet`

- Symptom 1 (missing menu UI): pressing `Enter` on the keyboard advanced past "Press START" into the main menu and played menu confirm sounds, but all menu panels, buttons, and selection highlights were invisible (`groups[seen=8651 exec=8651 empty=82376]`, `textures[cached=4/1024]`).
- Cause 1: a 25 s traced run (`RSX_TRACE=3000000`, 22,469 `BEGIN/END` groups, all `PRIM_TRIANGLES=5`) showed that **20,207 of 22,469 groups** send vertex indices inline in the FIFO via **`NV4097_ARRAY_ELEMENT16` (`0x180C`, 332,077 words: u16 `index0 = data & 0xFFFF`, `index1 = data >> 16`)** and **`NV4097_ARRAY_ELEMENT32` (`0x1810`, 232 words: u32 `index = data`)** without `0x1814`/`0x1824`. Because ps3recomp did not handle `0x180C`/`0x1810`, `sink_end` saw `dc.n_packets == 0` and dropped 90.5 % of draws.
- Fix 1 (**[runtime]**, branch `fix/rsx-array-element`): implemented `0x180C` and `0x1810` in `libs/video/rsx_dispatch.h/.c`, `libs/video/rsx_live_draw.c`, and `libs/video/rsx_draw_engine.c`. Rebuilt `ps3recomp_runtime.lib` and relinked `civrev.exe`.
- Result 1: `groups[empty]` dropped from **82,376 → 0** (`groups[seen=23003 exec=23003 empty=0]`, `textures[cached=27/1024]`). Title banner ("PREMI START") and all main menu panels, buttons ("Giocatore singolo / Multigiocatore / Gioca ora / Extra / Opzioni"), and selection highlights render cleanly.

- Symptom 2 (PhysX queue entries reading as all zeros): popped 16-byte entries from `0x01B72900` were all zero.
- Cause 2: the PhysX SPU task (image 9, `spu_0008_at_0183EB80`, push code around `0x6C1C`-`0x7088`) reads the queue header as `+0x08` u32 entry size, `+0x0C` u32 depth, `+0x10` u64 buffer EA, `+0x18` event port, `+0x1C` direction. Upstream `_cellSpursQueueInitialize` used CellSyncLFQueue's offsets (`+0x10` size, `+0x18` buffer EA), so the SPU read size 0 and copied nothing.
- Fix 2: `src/port/civrev_hle.cpp` overrides `_cellSpursQueueInitialize` (`0x082BFB09`) with that layout (see the comment block in the file) and updates `civrev_CellSpursQueuePopBody` (`0x91066667`). Also added handlers for `cellSpursQueueDetachLv2EventQueue` (`0x039D70B7`), `_sys_spu_printf_initialize` (`0x45FE2FCE`), `_sys_spu_printf_finalize` (`0xDD0C1E09`), `cellAudioSetPortLevel` (`0x56DFE179`), and `inet_addr` (`0xDABBC2C0`).
- Result 2: PhysX SPU tasks now DMA real 16-byte result payloads (`01BA7844 00000000 ...`) into `0x01B72900`; 0 unresolved NIDs fire through the title screen and main menu.

- Symptom 3 (SPU abort on entering "Gioca ora"): pressing `Enter` on "Gioca ora" ("Play now") aborted `image=6` (`spu_0005_at_017A9F80.elf`, 325 KB PhysX solver task): `[spu] img=6 branched into unlifted LS 0x20190 (lr=0x20150) -- ending the job`.
- Cause 3: `spu_func_00020118` (`__do_global_ctors_aux`, called from `_init` `0x201FC` inside `_start`) walks the `.ctors` function pointer table at LS `0x22000` (`[0x20190, 0x05288, 0x16B48, 0x1A628, 0x1FD98, 0x200F0]`). `tools/find_spu_functions.py` never seeded `.ctors`/`.dtors`/`.init_array`/`.fini_array` sections. In addition, `collect_jump_table_targets` capped `.rodata` jump tables at `max_entries=32`, truncating 49-entry (7×7) 2D dispatch tables such as `0x23BA0` in `spu_0006_at_017F9580.elf`.
- Fix 3 (**[runtime]**): added `collect_ctor_dtor_targets()` and raised `collect_jump_table_targets` `max_entries` from `32` to `128` in `tools/find_spu_functions.py`. Re-lifted SPU workloads (`image=6`: 216 → 226 functions; `image=7`: 144 → 156 functions) and rebuilt `civrev.exe`.
- Result 3: entering "Gioca ora" now renders the full **3D Civilization Selection screen ("Scegli la tua civiltà")** with animated 3D Mao Zedong, leader portraits, era icons, and 3D city background, and pressing `Enter` again advances to the **Match Loading screen ("Caricamento... La scoperta del manufatto Cavalieri Templari...")** and opens `DawnOfMan.bik` (`textures[cached=73/1024]`, `groups[seen=87718 exec=87718 empty=0]`). `image=6` runs to completion (`RETURNED rc=0`), issues MFC list DMAs, and pops from `q=0x01B73200` 7 times cleanly.

- Symptom 4 (crash at match entry, frame ~3000): as the match finishes loading, `image=1` (`spu_0000_at_01764A80.elf`, Firaxis `CIV_REVSPURS` frustum culling task) is dispatched 4 times, two unresolved NIDs fire (`0xA121A224` and `0x13AE18F3`), and PPU thread 1 crashes calling `NULL` in `func_00A60D20` (`from 0x00AA74C8` inside `func_00AA741C`).
- Cause 4: `func_00AA77A8` (`ppu_recomp_047.cpp`) dispatches `2 * nSpus` tasks of `image=1`, attaching each task's 128-byte `CellSpursTaskExitCode` container (`*(u32*)(r31+0x31C) + i*0x80`) via **`cellSpursTaskAttributeSetExitCodeContainer` (`0xA121A224`)**. `image=1` (`spu_func_00003278`) culls up to 2,048 bounding boxes (`arg.word1`) against 6 frustum planes (`arg.word0`), DMAs visible object pointers out to `arg.word3`, and passes `r3 = visible_count` (`gpr[96]`) to `cellSpursTaskExit` (`spu_func_00003900`), which writes `r3` at **`LS[0x2FD0]` (`STC_TASK_EXIT_CODE`)** and halts via `0xA70`. PPU `func_00AA741C`/`func_00AA73A0` then calls **`cellSpursTaskExitCodeGet` (`0x13AE18F3`)** to wait for completion and write `visible_count` into `*(u32*)(r27 + 0x10 + 4*i)`. Because `0xA121A224` and `0x13AE18F3` are unimplemented (and `spu_async_run` ignores `LS[0x2FD0]`), PPU reads stale `0x144` (324) at `r27+0x10` when 0 objects were visible and calls `func_00A60D20(NULL)`.
- Next fix in progress: implement `cellSpursTaskAttributeSetExitCodeContainer` (`0xA121A224`), `cellSpursTaskExitCodeGet` (`0x13AE18F3`), `cellSpursTaskExitCodeTryGet` (`0xE717AC73`), and forward `LS[0x2FD0]` (`STC_TASK_EXIT_CODE`) on SPU task exit.

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
