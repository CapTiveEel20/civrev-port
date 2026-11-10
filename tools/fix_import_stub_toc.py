"""Post-process lifted PPU code: make every import stub save the caller's TOC.

Why: a real PS3 import stub (.lib.stub trampoline) does `std r2,40(r1)` before
jumping into the firmware, and the caller restores its TOC afterwards with
`ld r2,40(r1)`. ps3_lifter --hle-stubs replaces the stub body with
`ps3_hle_call(nid, ctx); return;` and relies on ps3_hle_call to write that slot.
But ps3_hle_call's fast path (ps3_hle_register_fast: sys_lwmutex_lock/unlock in
ps3recomp v0.19.0) returns before the slot is written. When such an import is
the first call in a fresh stack frame, the slot still holds 0, the caller
reloads r2 = 0, and every later global access reads through a null TOC.
Civ Rev hits this in its C runtime start-up (func_013D2A90).

Fix: emit the store the real stub does. Idempotent; latin-1 safe (the lifted
files contain non-UTF-8 bytes).

Usage: python fix_import_stub_toc.py <src/recomp dir>
"""
import pathlib
import re
import sys

STUB = re.compile(r"(?m)^(\s*)(ps3_hle_call\(0x[0-9A-Fa-f]{8}u, ctx\); return;\s+/\* import stub \*/)")
SAVE = "vm_write64(ctx->gpr[1] + 0x28, ctx->gpr[2]);  /* std r2,40(r1) */ "


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    total = fixed = 0
    for path in sorted(pathlib.Path(sys.argv[1]).glob("ppu_recomp_*.cpp")):
        text = path.read_bytes().decode("latin-1")
        n_stub = len(STUB.findall(text))
        if not n_stub:
            continue
        total += n_stub
        # Already-fixed lines start with vm_write64, so STUB (anchored at the
        # line start on ps3_hle_call) skips them: n counts only new fixes.
        new, n = STUB.subn(lambda m: m.group(1) + SAVE + m.group(2), text)
        if new != text:
            path.write_bytes(new.encode("latin-1"))
            fixed += n
    already = len(re.findall(re.escape(SAVE.strip()), "".join(
        p.read_bytes().decode("latin-1") for p in pathlib.Path(sys.argv[1]).glob("ppu_recomp_*.cpp"))))
    print(f"import stubs: {total} unfixed found, {fixed} fixed now, {already} total with TOC save")
    if already == 0:
        print("ERROR: no import stubs found -- lifter output format changed?")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
