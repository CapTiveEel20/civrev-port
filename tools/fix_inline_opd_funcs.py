"""Add functions that are reachable only through INLINE function descriptors.

Why: a PPU function pointer on the PS3 points at an 8-byte descriptor
{code address, TOC}. Compiled code keeps these in the .opd section, and
ps3recomp's ppu_loader.py builds its function list from .opd (plus direct
calls). Civ Rev also contains hand-written routines (108 of them, near
0x00FBABE0-0x00FC41A8, most likely PhysX) whose descriptor sits INSIDE .text,
immediately before the code:

    desc:  .long desc+8, 0        # {code = next word, toc = 0}
    code:  stwu r1,-N(r1)         # prologue
           ...

Nothing calls them directly, so the loader merges them all into the preceding
compiled function (0x00FB94F0..0x00FC46E0). The lifter never emits them, and
the first indirect call into one aborts the run:
    [ppu] FATAL: stuck calling 0x00FC2EA8 (2000 times)

Fix: scan the executable segment for that pattern, end the swallowing entry at
the first descriptor, and add one entry per routine (ending at the next
descriptor; the last one at the swallowing entry's old end -- the lifter's own
"prologue after blr" rule splits anything further inside it).

Rewrites the function list in place. Idempotent.

Usage: python fix_inline_opd_funcs.py <EBOOT.elf> <EBOOT.functions.json>
"""
import json
import struct
import sys

STWU_R1 = 0x9421  # stwu r1,-N(r1): upper 16 bits of the frame-opening instruction


def exec_segments(elf: bytes):
    phoff, = struct.unpack_from(">Q", elf, 0x20)
    phentsz, phnum = struct.unpack_from(">HH", elf, 0x36)
    for i in range(phnum):
        p_type, p_flags, p_off, p_vaddr, _, p_filesz = struct.unpack_from(">IIQQQQ", elf, phoff + i * phentsz)
        if p_type == 1 and p_flags & 1:  # PT_LOAD, executable
            yield p_off, p_vaddr, p_filesz


def inline_descriptors(elf: bytes):
    found = []
    for off, vaddr, size in exec_segments(elf):
        for a in range(0, size - 12, 4):
            code, _toc, first = struct.unpack_from(">III", elf, off + a)
            va = vaddr + a
            if code == va + 8 and (first >> 16) == STWU_R1:
                found.append(va)
    return found


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    elf = open(sys.argv[1], "rb").read()
    funcs = json.load(open(sys.argv[2]))
    descs = inline_descriptors(elf)
    starts = {int(f["start"], 16) for f in funcs}
    todo = [d for d in descs if d + 8 not in starts]
    print(f"inline descriptors: {len(descs)}, missing from function list: {len(todo)}")
    if not todo:
        return 0

    out, added, trimmed = [], 0, 0
    for f in funcs:
        s, e = int(f["start"], 16), int(f["end"], 16)
        inside = [d for d in todo if s < d + 8 < e]
        if not inside:
            out.append(f)
            continue
        if s < inside[0]:
            out.append(dict(f, end=hex(inside[0])))
            trimmed += 1
        for k, d in enumerate(inside):
            end = inside[k + 1] if k + 1 < len(inside) else e
            out.append({"start": hex(d + 8), "end": hex(end), "toc": "0x0", "opd": hex(d)})
            added += 1
    if added != len(todo):
        print(f"error: {len(todo) - added} descriptors are outside every listed function", file=sys.stderr)
        return 1
    out.sort(key=lambda f: int(f["start"], 16))
    with open(sys.argv[2], "w") as fp:
        json.dump(out, fp, indent=1)
    print(f"added {added} functions, trimmed {trimmed} entries -> {len(out)} total")
    return 0


if __name__ == "__main__":
    sys.exit(main())
