/*
 * civrev_hle.cpp -- Civ Rev-specific HLE overrides.
 *
 * Handlers registered here with ps3_hle_register_ctx() are dispatched BEFORE
 * the generic NID table (ps3recomp runtime/ppu/ppu_hle.cpp: ctx handlers are
 * searched first), so they replace a ps3recomp handler for this game only,
 * without editing upstream or the generated src/gen/ppu_hle_nids.cpp.
 */
#include <stdint.h>
#include <stdio.h>
#include "ppu_recomp.h"   /* ppu_context; vm_read8/16/32 (guest addr -> big-endian read) */

extern "C" void ps3_hle_register_ctx(uint32_t nid, const char* name, void (*fn)(ppu_context*));

/* ---------------------------------------------------------------------------
 * cellOvis: int cellOvisGetOverlayTableSize(const char* spuElf)   NID 0x82F294B2
 *
 * PhysX calls this once per SPU program it loads (guest 0x00FED62C), passing a
 * pointer to an SPU ELF image in r3, and reads the table size from the RETURN
 * value: 0 = no overlays (program skipped), anything else = bytes to allocate.
 *
 * ps3recomp's stub (libs/misc/cellOvis.c) uses a different shape --
 * (filePath, u32* tableSize) -- and first requires a cellOvisInit() the game
 * never calls, so it returns 0x80410701. PhysX takes that as a ~2 GB size, the
 * allocation fails, and boot stops with "PhysX: Cannot run without SPURS".
 *
 * An SPU ELF that uses overlays carries an ".ovtab" section (the overlay table
 * the SPU toolchain emits). None of the game's 9 SPU images has one, so the
 * correct answer here is 0. If an ELF with overlays ever shows up we still
 * return 0, but say so loudly: that case would need a real implementation.
 * ------------------------------------------------------------------------- */
static int spu_elf_has_section(uint32_t elf, const char* want)
{
    const uint32_t shoff    = vm_read32(elf + 0x20);
    const uint16_t shentsz  = vm_read16(elf + 0x2E);
    const uint16_t shnum    = vm_read16(elf + 0x30);
    const uint16_t shstrndx = vm_read16(elf + 0x32);
    if (!shoff || !shnum || shstrndx >= shnum || shentsz < 0x28) return 0;
    const uint32_t strtab = elf + vm_read32(elf + shoff + shstrndx * shentsz + 0x10);
    for (uint16_t i = 0; i < shnum; i++) {
        const uint32_t name = strtab + vm_read32(elf + shoff + i * shentsz);
        uint32_t k = 0;
        while (want[k] && vm_read8(name + k) == (uint8_t)want[k]) k++;
        if (!want[k] && vm_read8(name + k) == 0) return 1;
    }
    return 0;
}

static void civrev_ovis_get_overlay_table_size(ppu_context* ctx)
{
    const uint32_t elf = (uint32_t)ctx->gpr[3];
    const int is_elf = elf && vm_read32(elf) == 0x7F454C46u; /* "\x7fELF" */
    if (!is_elf)
        fprintf(stderr, "[civrev] cellOvisGetOverlayTableSize(0x%08X): not an ELF, returning 0\n", elf);
    else if (spu_elf_has_section(elf, ".ovtab"))
        fprintf(stderr, "[civrev] cellOvisGetOverlayTableSize(0x%08X): ELF HAS OVERLAYS -- "
                        "unsupported, returning 0\n", elf);
    ctx->gpr[3] = 0;
}

namespace {
struct CivrevHleRegistrar {
    CivrevHleRegistrar()
    {
        ps3_hle_register_ctx(0x82F294B2u, "cellOvisGetOverlayTableSize(civrev)",
                             civrev_ovis_get_overlay_table_size);
    }
} g_civrev_hle_registrar;
}
