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
#include <string.h>
#include <atomic>
#include <chrono>
#include <thread>
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

/* ---------------------------------------------------------------------------
 * cellSpurs queue layout (128-byte big-endian line, 128-byte aligned)
 *
 * Derived directly from the recompiled SPU task code in spu_0008_at_0183EB80
 * (spu_func_00006C1C..0x7088 = cellSpursQueuePushBegin/End, 0x7398..0x7580):
 *   +0x00  s32 pop index   (~v while a pop is in progress; mod 2*depth)
 *   +0x04  s32 push index  (~v while a push DMA is in flight; mod 2*depth)
 *   +0x08  u32 entry size  (read at 0x6F04: rotqbyi(line0, 8) -> MFC_Size)
 *   +0x0C  u32 depth       (read at 0x6C1C: rotqbyi(line0, 12) -> ring modulus)
 *   +0x10  u64 buffer EA   (read at 0x6F04: line1 + slot*size -> MFC_EAH/EAL)
 *   +0x18  s32 event port  (read at 0x7088: -1 when no PPU event port attached)
 *   +0x1C  u32 direction   (read at 0x6C1C: 2 = PPU2SPU rejects SPU push)
 *   +0x20..+0x5F           waiter rings (0 when empty)
 *   +0x60  u64 owner EA    (read at 0x7438: compared with taskset EA at 0x1C0)
 *
 * ps3recomp's _cellSpursQueueInitialize copied CellSyncLFQueue's offsets (+0x10
 * size, +0x18 buffer_ea), so the SPU read +0x08 size = 0 and DMA'd 0 bytes to
 * EA 0x10_00000080, leaving all popped entries at 0x01B72900 zero.
 * ------------------------------------------------------------------------- */
extern "C" {
extern uint8_t* vm_base;   /* host base of guest memory */
void spu_lockline_lock(void);
void spu_lockline_unlock(void);
void spu_coh_notify_write(uint32_t ea);
}

/* Raw big-endian guest access for use INSIDE spu_lockline_lock(). vm_read/
 * vm_write* must not be used there: on a line an SPU has reserved, vm_write*
 * (ppu_loader.cpp VM_WRITE_COH) takes spu_lockline_lock itself, which is not
 * recursive -- a self-deadlock (seen: PhysX's blocking pop froze the game).
 * Same pattern as ps3recomp's spu_taskset2_set_exit. */
static uint32_t raw_be32(uint32_t ea)
{
    const uint8_t* p = vm_base + ea;
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}
static void raw_put_be32(uint32_t ea, uint32_t v)
{
    uint8_t* p = vm_base + ea;
    p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16); p[2] = (uint8_t)(v >> 8); p[3] = (uint8_t)v;
}

static const uint32_t SPURS_TASK_ERROR_AGAIN        = 0x80410901u;
static const uint32_t SPURS_TASK_ERROR_INVAL        = 0x80410902u;
static const uint32_t SPURS_TASK_ERROR_ALIGN        = 0x80410910u;
static const uint32_t SPURS_TASK_ERROR_NULL_POINTER = 0x80410911u;

static void civrev_spurs_queue_init(ppu_context* ctx)
{
    const uint32_t spurs   = (uint32_t)ctx->gpr[3];
    const uint32_t taskset = (uint32_t)ctx->gpr[4];
    const uint32_t q       = (uint32_t)ctx->gpr[5];
    const uint32_t buf     = (uint32_t)ctx->gpr[6];
    const uint32_t size    = (uint32_t)ctx->gpr[7];
    const uint32_t depth   = (uint32_t)ctx->gpr[8];
    const uint32_t dir     = (uint32_t)ctx->gpr[9];
    if (!q || !buf)        { ctx->gpr[3] = (int64_t)(int32_t)SPURS_TASK_ERROR_NULL_POINTER; return; }
    if (!size || !depth)   { ctx->gpr[3] = (int64_t)(int32_t)SPURS_TASK_ERROR_INVAL; return; }
    if (q & 0x7F)          { ctx->gpr[3] = (int64_t)(int32_t)SPURS_TASK_ERROR_ALIGN; return; }

    for (uint32_t o = 0; o < 128; o += 4) vm_write32(q + o, 0);
    vm_write32(q + 0x08, size);
    vm_write32(q + 0x0C, depth);
    vm_write64(q + 0x10, (uint64_t)buf);
    vm_write32(q + 0x18, 0xFFFFFFFFu); /* no PPU event port attached */
    vm_write32(q + 0x1C, dir);
    vm_write64(q + 0x60, (uint64_t)(taskset ? taskset : spurs));
    vm_write64(q + 0x70, (uint64_t)(taskset ? taskset : spurs));
    memset(vm_base + buf, 0, (size_t)size * depth);

    fprintf(stderr, "[civrev] _cellSpursQueueInitialize(taskset=0x%08X q=0x%08X buf=0x%08X size=%u depth=%u dir=%u)\n",
            taskset, q, buf, size, depth, dir);
    ctx->gpr[3] = 0;
}

static uint32_t spurs_queue_try_pop(uint32_t q, uint32_t buf, int peek)
{
    static std::atomic<int> s_logged{0};
    spu_lockline_lock();   /* the SPU side updates this line with GETLLAR/PUTLLC under the same lock */
    const int32_t  w0   = (int32_t)raw_be32(q + 0x00);
    const int32_t  w1   = (int32_t)raw_be32(q + 0x04);
    const uint32_t size = raw_be32(q + 0x08);
    const int32_t  mod  = (int32_t)raw_be32(q + 0x0C);
    const uint32_t data = raw_be32(q + 0x14);   /* low word of the u64 buffer EA at +0x10 */
    if (mod <= 0 || !size || size > 0x4000 || !data) { spu_lockline_unlock(); return SPURS_TASK_ERROR_INVAL; }

    /* While an SPU push DMA is in flight, PushBegin stores ~push at +0x04 and
     * PushEnd commits (push + 1) % (2*mod) only after the DMA tag completes.
     * So ~w1 (when w1 < 0) is the uncommitted index before the in-flight push. */
    const int32_t pop  = w0 < 0 ? ~w0 : w0;
    const int32_t push = w1 < 0 ? ~w1 : w1;
    const int32_t n    = push >= pop ? push - pop : push - pop + 2 * mod;
    if (n == 0) { spu_lockline_unlock(); return SPURS_TASK_ERROR_AGAIN; }

    const uint32_t src = data + (uint32_t)(pop % mod) * size;
    memcpy(vm_base + buf, vm_base + src, size);
    if (!peek) {
        raw_put_be32(q + 0x00, (uint32_t)((pop + 1) % (2 * mod)));
        spu_coh_notify_write(q);   /* drop SPU reservations on the line: a full-queue pusher re-reads it */
    }
    spu_lockline_unlock();

    if (s_logged.fetch_add(1) < 6)
        fprintf(stderr, "[civrev] QueuePop q=0x%08X idx %d/%d (n=%d depth=%d) slot=%d entry=%08X %08X %08X %08X "
                        "waiters@+0x20=%08X %08X%s\n",
                q, pop, push, n, mod, pop % mod, vm_read32(buf), vm_read32(buf + 4), vm_read32(buf + 8),
                vm_read32(buf + 12), vm_read32(q + 0x20), vm_read32(q + 0x24), peek ? " (peek)" : "");
    return 0;
}

static void civrev_spurs_queue_pop_body(ppu_context* ctx)
{
    const uint32_t q = (uint32_t)ctx->gpr[3], buf = (uint32_t)ctx->gpr[4];
    const int peek = (uint32_t)ctx->gpr[5] != 0, blocking = (uint32_t)ctx->gpr[6] != 0;
    uint32_t rc;
    if (!q || !buf)    rc = SPURS_TASK_ERROR_NULL_POINTER;
    else if (q & 0x7F) rc = SPURS_TASK_ERROR_ALIGN;
    else {
        static std::atomic<int> s_calls{0};
        if (s_calls.fetch_add(1) < 12)
            fprintf(stderr, "[civrev] QueuePop call q=0x%08X peek=%d blocking=%d line=%08X %08X %08X %08X size=%u buf=0x%08X lr=0x%08X\n",
                    q, peek, blocking, vm_read32(q), vm_read32(q + 4), vm_read32(q + 8), vm_read32(q + 12),
                    vm_read32(q + 0x08), (uint32_t)vm_read64(q + 0x10), (uint32_t)ctx->lr);
        rc = spurs_queue_try_pop(q, buf, peek);
        /* Blocking: the real call sleeps on the queue's lv2 event queue until a
         * task pushes. Poll instead; results arrive within a few ms. */
        const auto t0 = std::chrono::steady_clock::now();
        int beats = 0;
        while (blocking && rc == SPURS_TASK_ERROR_AGAIN) {
            std::this_thread::sleep_for(std::chrono::microseconds(200));
            rc = spurs_queue_try_pop(q, buf, peek);
            const auto secs = std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now() - t0).count();
            if (beats < 4 && secs >= 2 * (beats + 1)) {
                beats++;
                fprintf(stderr, "[civrev] QueuePop q=0x%08X: blocking pop still empty after %lld s, line=%08X %08X %08X %08X +0x20=%08X %08X\n",
                        q, (long long)secs, vm_read32(q), vm_read32(q + 4), vm_read32(q + 8), vm_read32(q + 12),
                        vm_read32(q + 0x20), vm_read32(q + 0x24));
                fflush(stderr);
            }
        }
    }
    ctx->gpr[3] = (uint64_t)(int64_t)(int32_t)rc;
}

/* ---------------------------------------------------------------------------
 * Trivial / offline stubs for unresolved imports
 * ------------------------------------------------------------------------- */
static void civrev_return_ok(ppu_context* ctx)
{
    ctx->gpr[3] = 0;
}

static void civrev_inet_addr(ppu_context* ctx)
{
    const uint32_t cp = (uint32_t)ctx->gpr[3];
    if (!cp) { ctx->gpr[3] = 0xFFFFFFFFull; return; }
    uint32_t parts[4] = {0, 0, 0, 0};
    int part = 0, digits = 0;
    for (uint32_t i = 0; i < 64; i++) {
        const uint8_t c = vm_read8(cp + i);
        if (c >= '0' && c <= '9') {
            parts[part] = parts[part] * 10u + (uint32_t)(c - '0');
            if (parts[part] > 255u) { ctx->gpr[3] = 0xFFFFFFFFull; return; }
            digits++;
        } else if (c == '.') {
            if (!digits || part >= 3) { ctx->gpr[3] = 0xFFFFFFFFull; return; }
            part++;
            digits = 0;
        } else if (c == 0) {
            break;
        } else {
            ctx->gpr[3] = 0xFFFFFFFFull;
            return;
        }
    }
    if (part != 3 || !digits) { ctx->gpr[3] = 0xFFFFFFFFull; return; }
    /* Big-endian guest u32 representation of a.b.c.d */
    ctx->gpr[3] = ((uint64_t)parts[0] << 24) | ((uint64_t)parts[1] << 16) |
                  ((uint64_t)parts[2] << 8)  | (uint64_t)parts[3];
}

namespace {
struct CivrevHleRegistrar {
    CivrevHleRegistrar()
    {
        ps3_hle_register_ctx(0x82F294B2u, "cellOvisGetOverlayTableSize(civrev)",
                             civrev_ovis_get_overlay_table_size);
        ps3_hle_register_ctx(0x082BFB09u, "_cellSpursQueueInitialize(civrev)",
                             civrev_spurs_queue_init);
        ps3_hle_register_ctx(0x91066667u, "_cellSpursQueuePopBody(civrev)",
                             civrev_spurs_queue_pop_body);
        ps3_hle_register_ctx(0x039D70B7u, "cellSpursQueueDetachLv2EventQueue(civrev)",
                             civrev_return_ok);
        ps3_hle_register_ctx(0x45FE2FCEu, "_sys_spu_printf_initialize(civrev)",
                             civrev_return_ok);
        ps3_hle_register_ctx(0xDD0C1E09u, "_sys_spu_printf_finalize(civrev)",
                             civrev_return_ok);
        ps3_hle_register_ctx(0x56DFE179u, "cellAudioSetPortLevel(civrev)",
                             civrev_return_ok);
        ps3_hle_register_ctx(0xDABBC2C0u, "inet_addr(civrev)",
                             civrev_inet_addr);
    }
} g_civrev_hle_registrar;
}
