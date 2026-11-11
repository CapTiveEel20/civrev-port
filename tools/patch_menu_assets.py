"""Tidy up the multiplayer menu art.

Makes one image packed inside `PS3_GAME/USRDIR/Resource/Common/Pregame.FPK`
(the badge of an online service that no longer exists, 512x128 DXT3) fully
transparent, in place (same size, nothing else in the archive moves).

DXT3 stores each 4x4 pixel block as 16 bytes: 8 bytes of explicit 4-bit alpha,
then 8 bytes of colour. Zeroing the 8 alpha bytes of every block = invisible.

A backup `Pregame.FPK.orig` is written next to the archive the first time.

Usage:
    python tools/patch_menu_assets.py [path\\to\\civrev-gamefiles\\vfs]
    python tools/patch_menu_assets.py [vfs] --restore
"""
import os
import shutil
import stat
import struct
import sys

TARGET = "poweredbygamespy.dds"


def fpk_entries(data):
    """Parse the FPK directory: yields (name, offset, size)."""
    if data[4:8] != b"FPK_":
        raise SystemExit("not an FPK archive")
    count = struct.unpack_from("<I", data, 0xA)[0]
    p = 0xE
    for _ in range(count):
        n = struct.unpack_from("<I", data, p)[0]
        p += 4
        name = data[p:p + n].decode("latin1")
        p += (n + 3) & ~3
        _ts, _zero, size, off = struct.unpack_from("<IIII", data, p)
        p += 16
        yield name, off, size


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    restore = "--restore" in sys.argv
    here = os.path.dirname(os.path.abspath(__file__))
    vfs = args[0] if args else os.path.join(here, "..", "..", "civrev-gamefiles", "vfs")
    fpk = os.path.join(vfs, "PS3_GAME", "USRDIR", "Resource", "Common", "Pregame.FPK")
    backup = fpk + ".orig"
    if not os.path.isfile(fpk):
        raise SystemExit("not found: " + fpk)
    os.chmod(fpk, os.stat(fpk).st_mode | stat.S_IWRITE)  # disc files are read-only

    if restore:
        if not os.path.isfile(backup):
            raise SystemExit("no backup to restore: " + backup)
        shutil.copyfile(backup, fpk)
        print("restored", fpk)
        return

    data = bytearray(open(fpk, "rb").read())
    hit = [e for e in fpk_entries(data) if e[0].lower() == TARGET]
    if not hit:
        raise SystemExit(TARGET + " not in archive")
    _, off, size = hit[0]
    dds = data[off:off + size]
    if dds[:4] != b"DDS " or dds[84:88] != b"DXT3":
        raise SystemExit("unexpected image format: %r %r" % (dds[:4], dds[84:88]))
    h, w = struct.unpack_from("<II", dds, 12)
    blocks = ((w + 3) // 4) * ((h + 3) // 4)
    first = off + 128  # skip the 128-byte DDS header
    if 128 + blocks * 16 > size:
        raise SystemExit("image smaller than expected")

    already = all(data[first + i * 16:first + i * 16 + 8] == b"\0" * 8 for i in range(blocks))
    if already:
        print("already hidden (%dx%d, %d blocks transparent)" % (w, h, blocks))
        return
    if not os.path.isfile(backup):
        shutil.copyfile(fpk, backup)
        print("backup:", backup)
    for i in range(blocks):
        b = first + i * 16
        data[b:b + 8] = b"\0" * 8
    open(fpk, "wb").write(data)
    print("hidden: %s %dx%d DXT3, %d blocks made transparent at archive offset 0x%X"
          % (TARGET, w, h, blocks, off))


if __name__ == "__main__":
    main()
