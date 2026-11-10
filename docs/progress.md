# Progress log

Newest first. Each entry: what we saw (symptom) → why (cause) → what fixed it.
Fixes in ps3recomp itself are marked **[runtime]**.

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
