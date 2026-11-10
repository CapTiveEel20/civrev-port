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
 * cellSpurs: int _cellSpursQueuePopBody(CellSpursQueue* q, void* buffer,
 *                                       unsigned isPeek, unsigned isBlocking)
 *                                                               NID 0x91066667
 *
 * PhysX starts one SPURS task per job; each task pushes a 16-byte result into
 * an SPU->PPU queue and exits. The PPU collects results with this call (guest
 * 0x00FECF68 blocking, 0x00FED000 polling: it expects 0x80410901 AGAIN when
 * empty). ps3recomp v0.19.0 has no handler, so the import returned 0 ("got
 * one") without removing anything. The read index never moved, the 128-entry
 * queue filled, every later task spun forever on its push (GETLLAR loop on the
 * queue line), PhysX ran out of task slots ("Error starting spurs task
 * 0x80410904") and the game gave up -- with ~128 spinning threads starving
 * the audio thread on the way.
 *
 * Queue line layout (big-endian, 128-byte aligned), the ring model ps3recomp's
 * own _cellSpursQueueInitialize / cellSpursQueueSize / cellSpursQueuePushBody
 * use: +0x00 pop index, +0x04 push index (a negative value ~v marks an
 * operation in progress on v), +0x0C ring modulus = depth, +0x10 entry size,
 * +0x18 buffer EA. Indices run modulo 2*depth; the slot is index % depth.
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

static uint32_t spurs_queue_try_pop(uint32_t q, uint32_t buf, int peek)
{
    static std::atomic<int> s_logged{0};
    spu_lockline_lock();   /* the SPU side updates this line with GETLLAR/PUTLLC under the same lock */
    const int32_t  w0   = (int32_t)raw_be32(q + 0x00);
    const int32_t  w1   = (int32_t)raw_be32(q + 0x04);
    const int32_t  mod  = (int32_t)raw_be32(q + 0x0C);
    const uint32_t size = raw_be32(q + 0x10);
    const uint32_t data = raw_be32(q + 0x1C);   /* low word of the u64 buffer EA at +0x18 */
    if (mod <= 0 || !size || size > 0x4000 || !data) { spu_lockline_unlock(); return SPURS_TASK_ERROR_INVAL; }

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
                    vm_read32(q + 0x10), (uint32_t)vm_read64(q + 0x18), (uint32_t)ctx->lr);
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

namespace {
struct CivrevHleRegistrar {
    CivrevHleRegistrar()
    {
        ps3_hle_register_ctx(0x82F294B2u, "cellOvisGetOverlayTableSize(civrev)",
                             civrev_ovis_get_overlay_table_size);
        ps3_hle_register_ctx(0x91066667u, "_cellSpursQueuePopBody(civrev)",
                             civrev_spurs_queue_pop_body);
    }
} g_civrev_hle_registrar;
}
