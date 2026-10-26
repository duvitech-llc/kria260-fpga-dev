/*
 * MicroBlaze V co-processor firmware (bare metal, no BSP).
 *
 * The A53 loads this program into the co-processor's memory, releases its
 * reset and talks to it through the mailbox (tcl/create_mbv.tcl):
 *   - on start it sends   { MSG_READY, FW_VERSION, 0 }
 *   - commands are three words { cmd, a, b }; the reply is three words
 *     { cmd | 0x8000_0000, x, y }:
 *       CMD_PING   a       -> { a + 1, interrupts taken so far }
 *       CMD_CRC32  addr,len-> { CRC-32 of len bytes at addr, cycles taken }
 *       CMD_SUM16  addr,n  -> { sum of n 32-bit words, cycles taken }
 * Messages arrive by interrupt: mailbox -> AXI INTC -> machine external
 * interrupt, vectored to trap() through the INTC's IVAR register.
 */
#include <stdint.h>

#define MBOX        0x40000000UL
#define INTC        0x41000000UL

#define REG(a)      (*(volatile uint32_t *)(a))

/* Mailbox (PG114) */
#define MB_WRDATA   REG(MBOX + 0x00)
#define MB_RDDATA   REG(MBOX + 0x08)
#define MB_STATUS   REG(MBOX + 0x10)
#define MB_RIT      REG(MBOX + 0x1C)
#define MB_IS       REG(MBOX + 0x20)
#define MB_IE       REG(MBOX + 0x24)
#define MB_CTRL     REG(MBOX + 0x2C)
#define MB_EMPTY    0x1U
#define MB_FULL     0x2U
#define MB_RTA      0x2U        /* receive threshold interrupt */

/* AXI INTC (PG099) */
#define INTC_ISR    REG(INTC + 0x00)
#define INTC_IER    REG(INTC + 0x08)
#define INTC_IAR    REG(INTC + 0x0C)
#define INTC_MER    REG(INTC + 0x1C)
#define INTC_IMR    REG(INTC + 0x20)
#define INTC_IVAR0  REG(INTC + 0x100)

#define FW_VERSION  0x00010000U
#define MSG_READY   0x80000000U
#define CMD_PING    0x1U
#define CMD_CRC32   0x2U
#define CMD_SUM32   0x3U

static volatile uint32_t irq_count;
static volatile uint32_t rx[16];
static volatile uint32_t rx_n;

static inline uint32_t cycles(void)
{
    uint32_t c;
    __asm__ volatile ("csrr %0, mcycle" : "=r"(c));
    return c;
}

static void mb_send(uint32_t w)
{
    while (MB_STATUS & MB_FULL) {
    }
    MB_WRDATA = w;
}

static uint32_t crc32(const uint8_t *p, uint32_t n)
{
    uint32_t c = 0xFFFFFFFFU;

    while (n--) {
        c ^= *p++;
        for (int k = 0; k < 8; k++) {
            c = (c >> 1) ^ (0xEDB88320U & (0U - (c & 1U)));
        }
    }
    return ~c;
}

static void command(uint32_t cmd, uint32_t a, uint32_t b)
{
    uint32_t t0 = cycles(), x = 0, y = 0;

    switch (cmd) {
    case CMD_PING:
        x = a + 1U;
        y = irq_count;
        break;
    case CMD_CRC32:
        x = crc32((const uint8_t *)a, b);
        y = cycles() - t0;
        break;
    case CMD_SUM32: {
        const volatile uint32_t *w = (const volatile uint32_t *)a;
        for (uint32_t i = 0; i < b; i++) {
            x += w[i];
        }
        y = cycles() - t0;
        break;
    }
    default:
        x = 0xBADC0DEU;
        y = cmd;
        break;
    }
    mb_send(cmd | 0x80000000U);
    mb_send(x);
    mb_send(y);
}

/* Progress words at a fixed place the A53 can read (0x8011_E000 for it):
 * [0] main-loop passes, [1] trap entries, [2] last mcause, [3] last mepc,
 * [4] INTC ISR seen in the trap, [5] words received, [6] {mailbox IS,
 * mailbox STATUS, INTC ISR, INTC IPR} while idle, [7] mip while idle. */
#define DBG ((volatile uint32_t *)0x0001E000)

/* Machine external interrupt: collect mailbox words into rx[]. */
__attribute__((interrupt("machine"), aligned(4))) static void trap(void)
{
    uint32_t mc, me;

    __asm__ volatile ("csrr %0, mcause" : "=r"(mc));
    __asm__ volatile ("csrr %0, mepc" : "=r"(me));
    DBG[1]++;
    DBG[2] = mc;
    DBG[3] = me;
    DBG[4] = INTC_ISR;
    if (INTC_ISR & 1U) {
        /* Clear first, then empty the FIFO: a word that arrives while the
         * FIFO is being emptied then raises the interrupt again. (Clearing
         * afterwards lost such a word on the board.) */
        MB_IS = MB_RTA;
        while (!(MB_STATUS & MB_EMPTY)) {
            uint32_t w = MB_RDDATA;
            if (rx_n < 16U) {
                rx[rx_n++] = w;
            }
            DBG[5]++;
        }
        INTC_IAR = 1U;
        irq_count++;
    }
}

int main(void)
{
    uint32_t mie = 1U << 11;        /* MEIE */

    for (int i = 0; i < 8; i++) {
        DBG[i] = 0;
    }
    MB_CTRL = 0x3U;                 /* empty both FIFOs */
    MB_RIT  = 0;                    /* interrupt when at least one word waits */
    MB_IS   = 0x7U;
    MB_IE   = MB_RTA;
    /* MicroBlaze V takes the handler address from the interrupt
     * controller (IVAR of the input), not from mtvec: with IVAR at its
     * reset value the first interrupt jumps into the start-up code. Set
     * both. Normal (not fast) mode: the handler acknowledges in IAR. */
    INTC_IVAR0 = (uint32_t)&trap;
    INTC_IMR = 0;
    INTC_IER = 1U;
    INTC_MER = 0x3U;                /* master enable, hardware interrupts */
    __asm__ volatile ("csrw mtvec, %0" :: "r"((uint32_t)&trap));
    __asm__ volatile ("csrs mie, %0" :: "r"(mie));
    __asm__ volatile ("csrsi mstatus, 0x8");    /* MIE */

    mb_send(MSG_READY);
    mb_send(FW_VERSION);
    mb_send(0);

    for (;;) {
        uint32_t c, a, b;

        /* No wfi here: this core is built with C_INTERRUPT_WAKEUP = 0, so an
         * interrupt does not wake it from wfi (found on the board: the
         * first ping was never answered). It spins, interrupts enabled,
         * and records the interrupt chain's state for the A53 to read. */
        DBG[0]++;
        __asm__ volatile ("csrci mstatus, 0x8");
        if (rx_n < 3U) {
            uint32_t mip;
            __asm__ volatile ("csrr %0, mip" : "=r"(mip));
            DBG[6] = REG(INTC + 0x04) | (INTC_ISR << 8) | (MB_STATUS << 16) | (MB_IS << 24); /* IPR, ISR, mbox */
            DBG[7] = mip;
            __asm__ volatile ("csrsi mstatus, 0x8");
            continue;
        }
        c = rx[0]; a = rx[1]; b = rx[2];
        for (uint32_t i = 3; i < rx_n; i++) {
            rx[i - 3] = rx[i];
        }
        rx_n -= 3U;
        __asm__ volatile ("csrsi mstatus, 0x8");
        command(c, a, b);
    }
}
