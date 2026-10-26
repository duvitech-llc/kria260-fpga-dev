/*
 * KV260 board test: MicroBlaze V co-processor (cpu=mbv).
 *
 * The A53 holds the co-processor in reset, writes its program (mbv_fw.h,
 * built by sw/mbv/build.py) into the co-processor's memory through the BRAM
 * window at 0x8010_0000, and releases the reset. They then talk through the
 * mailbox; the co-processor's replies interrupt the A53 (pl_ps_irq0[3]).
 * Checks:
 *   - program written and read back
 *   - the co-processor starts and says "ready"
 *   - 1000 ping round trips, each answered correctly
 *   - CRC-32 of 32 KB that the A53 put in the shared memory, computed by
 *     the co-processor, equals the A53's own result
 */
#include "board_test.h"

#ifdef HAVE_MBV
#include "xil_io.h"
#include "xil_printf.h"
#include "xiltimer.h"
#include "sleep.h"
#include "xil_exception.h"
#include "mbv_fw.h"

/* Mailbox registers (PG114), PS side = S0 */
#define MB_WRDATA   0x00U
#define MB_RDDATA   0x08U
#define MB_STATUS   0x10U
#define MB_RIT      0x1CU
#define MB_IS       0x20U
#define MB_IE       0x24U
#define MB_CTRL     0x2CU
#define MB_EMPTY    0x1U
#define MB_FULL     0x2U
#define MB_RTA      0x2U

#define MSG_READY   0x80000000U
#define CMD_PING    0x1U
#define CMD_CRC32   0x2U

#define MBV_SHARED      0x10000U        /* co-processor address of the shared buffer */
#define MBV_SHARED_LEN  (32U * 1024U)
#define MBV_DBG         0x1E000U        /* firmware progress words (sw/mbv/main.c) */

static u32 shared_copy[MBV_SHARED_LEN / 4U];
static volatile u32 rxq[64];
static volatile u32 rx_head, rx_tail, mb_irqs;

static void mbox_isr(void *ref)
{
    (void)ref;
    while (!(Xil_In32(MBV_MBOX_BASE + MB_STATUS) & MB_EMPTY)) {
        rxq[rx_head & 63U] = Xil_In32(MBV_MBOX_BASE + MB_RDDATA);
        rx_head++;
    }
    Xil_Out32(MBV_MBOX_BASE + MB_IS, MB_RTA);
    mb_irqs++;
}

/* Wait for one word from the co-processor; 0 on success. */
static int mb_get(u32 *w, u32 timeout_us)
{
    while (rx_tail == rx_head) {
        if (timeout_us-- == 0U) {
            return -1;
        }
        usleep(1);
    }
    *w = rxq[rx_tail & 63U];
    rx_tail++;
    return 0;
}

static void mb_put(u32 w)
{
    while (Xil_In32(MBV_MBOX_BASE + MB_STATUS) & MB_FULL) {
    }
    Xil_Out32(MBV_MBOX_BASE + MB_WRDATA, w);
}

/* Send { cmd, a, b }, wait for { cmd | 0x8000_0000, x, y }. */
static int mbv_call(u32 cmd, u32 a, u32 b, u32 *x, u32 *y, u32 timeout_us)
{
    u32 r;

    mb_put(cmd);
    mb_put(a);
    mb_put(b);
    if (mb_get(&r, timeout_us) || mb_get(x, timeout_us) || mb_get(y, timeout_us)) {
        return -1;
    }
    return (r == (cmd | 0x80000000U)) ? 0 : -1;
}

static u32 crc32(const volatile u8 *p, u32 n)
{
    u32 c = 0xFFFFFFFFU;
    int k;

    while (n--) {
        c ^= *p++;
        for (k = 0; k < 8; k++) {
            c = (c >> 1) ^ (0xEDB88320U & (0U - (c & 1U)));
        }
    }
    return ~c;
}

void test_mbv(void)
{
    u32 i, bad = 0, w0, w1, w2, x, y, seed = 0x12345678U, mine;
    XTime t0, t1;

    /* 1. Hold in reset, load the program, check it. */
    Xil_Out32(MBV_CTRL_BASE + GPIO_DATA, 0);
    usleep(10);
    for (i = 0; i < MBV_FW_WORDS; i++) {
        Xil_Out32(MBV_MEM_BASE + 4U * i, mbv_fw[i]);
    }
    for (i = 0; i < MBV_FW_WORDS; i++) {
        if (Xil_In32(MBV_MEM_BASE + 4U * i) != mbv_fw[i]) {
            bad++;
        }
    }
    xil_printf("  program: %d bytes written to 0x%08lx, %lu words wrong\r\n",
               MBV_FW_WORDS * 4, (u32)MBV_MEM_BASE, bad);
    if (bad) {
        result("MBV", 0);
        return;
    }

    /* 2. Let it run, then set up the mailbox and its interrupt. The mailbox
     * is only touched once the co-processor runs: in the first hardware
     * version it shared the co-processor's reset and did not answer before.
     * Its FIFOs are not flushed here; the co-processor empties them itself
     * when it starts, and its "ready" message may already be waiting. */
    rx_head = rx_tail = mb_irqs = 0;
    if (irq_attach(IRQ_MBV_MBOX, mbox_isr, NULL, 0) != XST_SUCCESS) {
        result("MBV", 0);
        return;
    }
    Xil_Out32(MBV_CTRL_BASE + GPIO_DATA, 1);            /* run */
    usleep(100);
    Xil_Out32(MBV_MBOX_BASE + MB_RIT, 0);
    Xil_Out32(MBV_MBOX_BASE + MB_IS, 0x7U);
    Xil_Out32(MBV_MBOX_BASE + MB_IE, MB_RTA);
    /* Words that arrived before the interrupt was enabled raise no new
     * interrupt: collect them once by hand. */
    Xil_ExceptionDisable();
    mbox_isr(NULL);
    Xil_ExceptionEnable();

    if (mb_get(&w0, 500000) || mb_get(&w1, 1000) || mb_get(&w2, 1000) || w0 != MSG_READY) {
        xil_printf("  no \"ready\" from the co-processor (got 0x%08lx)\r\n", w0);
        result("MBV", 0);
        return;
    }
    xil_printf("  co-processor running, firmware version 0x%08lx\r\n", w1);

    /* 3. Ping round trips. */
    XTime_GetTime(&t0);
    for (i = 0; i < 1000U; i++) {
        if (mbv_call(CMD_PING, i, 0, &x, &y, 10000) || x != i + 1U) {
            u32 k;
            xil_printf("  ping %lu failed (reply 0x%08lx 0x%08lx, %lu words queued, %lu A53 interrupts)\r\n",
                       i, x, y, rx_head - rx_tail, mb_irqs);
            xil_printf("  co-processor markers (loops, traps, mcause, mepc, ISR in trap, words, {mbox IS,STATUS,INTC ISR,IPR}, mip):");
            for (k = 0; k < 8U; k++) {
                xil_printf(" 0x%08lx", Xil_In32(MBV_MEM_BASE + MBV_DBG + 4U * k));
            }
            xil_printf("\r\n  run bit %lu, code[0..1] 0x%08lx 0x%08lx (expect 0x%08x 0x%08x)\r\n",
                       Xil_In32(MBV_CTRL_BASE + GPIO_DATA), Xil_In32(MBV_MEM_BASE),
                       Xil_In32(MBV_MEM_BASE + 4U), mbv_fw[0], mbv_fw[1]);
            result("MBV", 0);
            return;
        }
    }
    XTime_GetTime(&t1);
    xil_printf("  1000 pings in %lu us; the co-processor took %lu interrupts, the A53 %lu\r\n",
               (u32)(((t1 - t0) * 1000000ULL) / COUNTS_PER_SECOND), y, mb_irqs);

    /* 4. Work on shared data: CRC-32 of 32 KB. The A53 keeps its own copy
     * for its reference result, and writes the co-processor's with 32-bit
     * accesses. */
    for (i = 0; i < MBV_SHARED_LEN / 4U; i++) {
        seed = seed * 1664525U + 1013904223U;
        shared_copy[i] = seed;
        Xil_Out32(MBV_MEM_BASE + MBV_SHARED + 4U * i, seed);
    }
    mine = crc32((const volatile u8 *)shared_copy, MBV_SHARED_LEN);
    xil_printf("  32 KB written to the shared memory, A53 CRC-32 0x%08lx; asking the co-processor\r\n", mine);
    if (mbv_call(CMD_CRC32, MBV_SHARED, MBV_SHARED_LEN, &x, &y, 2000000)) {
        xil_printf("  CRC command got no answer\r\n");
        result("MBV", 0);
        return;
    }
    xil_printf("  CRC-32 of 32 KB: co-processor 0x%08lx in %lu cycles (%lu ms at 100 MHz), A53 0x%08lx\r\n",
               x, y, y / 100000U, mine);
    result("MBV", x == mine);
}
#endif
