"""Print the end of the last executable section of a PPU ELF, as 0x%08X.

relift.ps1 passes this as --code-end: it sits just past the import stubs
(.sceStub.text), so --hle-stubs can rewrite them and nothing above (read-only
data in the same segment) is mistaken for code.

    BLES00238 1.00: 0x01416CEC (223 import stubs)
    BLES00238 1.30: 0x0141FC5C (224 import stubs)
"""
import struct
import sys

SHF_EXECINSTR = 0x4


def code_end(elf: bytes) -> int:
    if elf[:4] != b"\x7fELF":
        raise ValueError("not a decrypted ELF")
    shoff, = struct.unpack_from(">Q", elf, 0x28)
    shentsize, shnum = struct.unpack_from(">HH", elf, 0x3A)
    if not shoff or not shnum:
        raise ValueError("ELF has no section headers")
    end = 0
    for i in range(shnum):
        _, _, flags, addr, _, size = struct.unpack_from(">IIQQQQ", elf, shoff + i * shentsize)
        if flags & SHF_EXECINSTR:
            end = max(end, addr + size)
    if not end:
        raise ValueError("ELF has no executable sections")
    return end


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: code_end.py EBOOT.elf")
    with open(sys.argv[1], "rb") as f:
        print(f"0x{code_end(f.read()):08X}")
