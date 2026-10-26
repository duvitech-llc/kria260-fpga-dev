/*
 * KV260 board test: PL peripherals (BRAM, PMOD, fan, PL timer interrupt, CDMA).
 */
#include "board_test.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "xiltimer.h"       /* XTime_GetTime, COUNTS_PER_SECOND (SDT BSP) */
#include "sleep.h"
#include "xttcps.h"

/* ---- BRAM ---------------------------------------------------------------- */
void test_bram(void)
{
    u32 i, bad = 0;

    for (i = 0; i < BRAM_SIZE; i += 4) {
        Xil_Out32(BRAM_BASE + i, 0xA5000000U ^ (i * 0x01010101U));
    }
    for (i = 0; i < BRAM_SIZE; i += 4) {
        if (Xil_In32(BRAM_BASE + i) != (0xA5000000U ^ (i * 0x01010101U))) {
            bad++;
        }
    }
    if (bad) {
        xil_printf("  %lu of %lu words wrong\r\n", bad, BRAM_SIZE / 4);
    }
    result("BRAM", bad == 0);
}

/* ---- PMOD ---------------------------------------------------------------- */
#ifdef HAVE_PMOD
static const char *const pmod_pin_name[8] = { "1", "2", "3", "4", "7", "8", "9", "10" };

void test_pmod(void)
{
    static const u32 pat[] = { 0x00, 0xFF, 0x55, 0xAA, 0x0F, 0xF0 };
    u32 i, got;
    int ok = 1;

    Xil_Out32(PMOD_BASE + GPIO_TRI, 0x00);          /* all outputs */
    for (i = 0; i < sizeof(pat) / sizeof(pat[0]); i++) {
        Xil_Out32(PMOD_BASE + GPIO_DATA, pat[i]);
        usleep(10);
        got = Xil_In32(PMOD_BASE + GPIO_DATA) & 0xFF;
        if (got != pat[i]) {
            xil_printf("  wrote 0x%02lx, pins read 0x%02lx\r\n", pat[i], got);
            ok = 0;
        }
    }
    Xil_Out32(PMOD_BASE + GPIO_TRI, 0xFF);          /* back to inputs */
    result("PMOD", ok);
}

/*
 * Wiring check: every pin is an input with a pull-up (xdc/kv260_pmod.xdc),
 * one at a time is driven low, and any other pin that follows it is wired
 * to it (a jumper, or a device that connects them). Not a pass/fail test.
 */
void pmod_loopback_scan(void)
{
    u32 i, j, in, idle, pairs = 0;

    Xil_Out32(PMOD_BASE + GPIO_DATA, 0x00);
    Xil_Out32(PMOD_BASE + GPIO_TRI, 0xFF);
    usleep(100);
    idle = Xil_In32(PMOD_BASE + GPIO_DATA) & 0xFF;
    if (idle != 0xFF) {
        xil_printf("  PMOD pins held low by something outside: 0x%02lx\r\n", (~idle) & 0xFF);
    }
    for (i = 0; i < 8; i++) {
        if (!(idle & (1U << i))) {
            continue;
        }
        Xil_Out32(PMOD_BASE + GPIO_TRI, 0xFF & ~(1U << i));   /* pin i drives 0 */
        usleep(100);
        in = Xil_In32(PMOD_BASE + GPIO_DATA) & 0xFF;
        for (j = i + 1; j < 8; j++) {
            if ((idle & (1U << j)) && !(in & (1U << j))) {
                xil_printf("  PMOD pin %s is connected to pin %s\r\n", pmod_pin_name[i], pmod_pin_name[j]);
                pairs++;
            }
        }
    }
    Xil_Out32(PMOD_BASE + GPIO_TRI, 0xFF);
    if (pairs == 0) {
        xil_printf("  PMOD: no pins wired together\r\n");
    }
}
#endif

/* ---- Fan ------------------------------------------------------------------ */
static const u32 fan_steps[] = { 100U, 75U, 50U, 25U };

#ifdef HAVE_FAN_RTL
/* Fabric PWM (src/rtl/common/fan_pwm.v): control bit 31 = software owns the
 * duty, bits 6..0 = duty %; channel 2 reads back the duty in use. */
#define FAN_SW      0x80000000U

static u32 last_duty = 0xFFU;

static u32 fan_rtl_duty(void)
{
    return Xil_In32(FAN_BASE + GPIO2_DATA) & 0x7FU;
}

void fan_start(void)
{
    u32 d0, d1, d2;
    int ok;

    Xil_Out32(FAN_BASE + GPIO_DATA, 0);                 /* fabric ramp */
    d0 = fan_rtl_duty();
    Xil_Out32(FAN_BASE + GPIO_DATA, FAN_SW | 40U);      /* software: 40 % */
    usleep(1000);
    d1 = fan_rtl_duty();
    Xil_Out32(FAN_BASE + GPIO_DATA, 0);                 /* back to the ramp */
    usleep(1000);
    d2 = fan_rtl_duty();
    xil_printf("  fabric duty %lu %%, software 40 %% -> %lu %%, released -> %lu %%\r\n", d0, d1, d2);
    ok = (d0 == fan_steps[0] || d0 == fan_steps[1] || d0 == fan_steps[2] || d0 == fan_steps[3]) &&
         d1 == 40U && d2 == d0;
    result("FAN", ok);
}

void fan_tick(void)
{
    u32 d = fan_rtl_duty();

    if (d != last_duty) {
        last_duty = d;
        xil_printf("Fan (fabric) -> %lu%%\r\n", d);
    }
}

#else
/* PS TTC0 channel 0 waveform -> EMIO -> fan pin A12.
 * ~100 Hz: 100 MHz LPD bus clock / 2^(5+1) = 1.5625 MHz tick, period 15625.
 * With WAVE_POLARITY the output is high from the start of the interval to
 * the match value, then low. fan_en_b is active low, so the high time is
 * (100 - percent) of the period. */
#define TTC0_CH0_BASE   0xFF110000UL
#define FAN_PRESCALE    5U
#define FAN_PERIOD      15625U

static XTtcPs fan_ttc;
static u32 fan_ticks, fan_idx;

static void fan_set_percent(u32 percent)
{
    if (percent > 100U) {
        percent = 100U;
    }
    XTtcPs_SetMatchValue(&fan_ttc, 0, (u32)(((u64)FAN_PERIOD * (100U - percent)) / 100U));
}

void fan_start(void)
{
    XTtcPs_Config *cfg = XTtcPs_LookupConfig(TTC0_CH0_BASE);

    if (cfg == NULL || XTtcPs_CfgInitialize(&fan_ttc, cfg, cfg->BaseAddress) != XST_SUCCESS) {
        result("FAN", 0);
        return;
    }
    /* The waveform output is on unless XTTCPS_OPTION_WAVE_DISABLE is given. */
    XTtcPs_SetOptions(&fan_ttc, XTTCPS_OPTION_INTERVAL_MODE | XTTCPS_OPTION_MATCH_MODE |
                                XTTCPS_OPTION_WAVE_POLARITY);
    XTtcPs_SetPrescaler(&fan_ttc, FAN_PRESCALE);
    XTtcPs_SetInterval(&fan_ttc, FAN_PERIOD);
    fan_set_percent(fan_steps[0]);
    XTtcPs_Start(&fan_ttc);
    result("FAN", 1);
}

void fan_tick(void)
{
    if ((++fan_ticks % 32U) == 0U) {
        fan_idx = (fan_idx + 1U) % 4U;
        fan_set_percent(fan_steps[fan_idx]);
        xil_printf("Fan -> %lu%%\r\n", fan_steps[fan_idx]);
    }
}
#endif

/* ---- PL timer interrupt (irq=1) -------------------------------------------
 * axi_timer counter 0 counts down from TLR0 and reloads, interrupting every
 * 10 ms. The handler acknowledges and counts. Registers from PG079. */
#ifdef HAVE_PL_TIMER
#define TCSR0       0x00U
#define TLR0        0x04U
#define TCSR_UDT    0x002U      /* count down */
#define TCSR_ARHT   0x010U      /* auto reload */
#define TCSR_LOAD   0x020U
#define TCSR_ENIT   0x040U
#define TCSR_ENT    0x080U
#define TCSR_TINT   0x100U      /* interrupt flag, write 1 to clear */

static volatile u32 timer_irqs;

static void pl_timer_isr(void *ref)
{
    (void)ref;
    Xil_Out32(PL_TIMER_BASE + TCSR0, Xil_In32(PL_TIMER_BASE + TCSR0) | TCSR_TINT);
    timer_irqs++;
}

void test_pl_timer_irq(void)
{
    u32 n;

    if (irq_attach(IRQ_PL_TIMER, pl_timer_isr, NULL, 0) != XST_SUCCESS) {
        result("PL IRQ", 0);
        return;
    }
    Xil_Out32(PL_TIMER_BASE + TCSR0, 0);
    Xil_Out32(PL_TIMER_BASE + TLR0, 1000000U - 1U);             /* 10 ms at 100 MHz */
    Xil_Out32(PL_TIMER_BASE + TCSR0, TCSR_LOAD | TCSR_TINT);
    timer_irqs = 0;
    Xil_Out32(PL_TIMER_BASE + TCSR0, TCSR_UDT | TCSR_ARHT | TCSR_ENIT | TCSR_ENT);
    usleep(500000);
    Xil_Out32(PL_TIMER_BASE + TCSR0, 0);                        /* stop */
    n = timer_irqs;
    xil_printf("  %lu interrupts in 0.5 s (expect 50)\r\n", n);
    result("PL IRQ", n >= 48U && n <= 52U);
}
#endif

/* ---- CDMA (dma=1) -----------------------------------------------------------
 * axi_cdma in simple mode copies a buffer to another in DDR through
 * S_AXI_HP1_FPD (not cache coherent: flush the source, invalidate the
 * destination). Completion interrupt on pl_ps_irq0[1]. Registers from PG034. */
#ifdef HAVE_CDMA
#define CDMACR      0x00U
#define CDMASR      0x04U
#define CDMA_SA     0x18U
#define CDMA_SA_MSB 0x1CU
#define CDMA_DA     0x20U
#define CDMA_DA_MSB 0x24U
#define CDMA_BTT    0x28U
#define CR_RESET    0x0004U
#define CR_IOC_EN   0x1000U
#define CR_ERR_EN   0x4000U
#define SR_IDLE     0x0002U
#define SR_ERRS     0x0070U
#define SR_IOC      0x1000U
#define SR_ERR_IRQ  0x4000U

#define CDMA_LEN    (1024U * 1024U)

static u8 cdma_src[CDMA_LEN] __attribute__((aligned(64)));
static u8 cdma_dst[CDMA_LEN] __attribute__((aligned(64)));
static volatile u32 cdma_done, cdma_sr;

static void cdma_isr(void *ref)
{
    (void)ref;
    cdma_sr = Xil_In32(CDMA_BASE + CDMASR);
    Xil_Out32(CDMA_BASE + CDMASR, SR_IOC | SR_ERR_IRQ);         /* acknowledge */
    cdma_done = 1;
}

void test_cdma(void)
{
    u32 i, bad = 0, t;
    XTime t0, t1;

    for (i = 0; i < CDMA_LEN; i++) {
        cdma_src[i] = (u8)(i * 7U + (i >> 11));
        cdma_dst[i] = 0;
    }
    Xil_DCacheFlushRange((UINTPTR)cdma_src, CDMA_LEN);
    Xil_DCacheFlushRange((UINTPTR)cdma_dst, CDMA_LEN);

    if (irq_attach(IRQ_CDMA, cdma_isr, NULL, 0) != XST_SUCCESS) {
        result("CDMA", 0);
        return;
    }
    Xil_Out32(CDMA_BASE + CDMACR, CR_RESET);
    for (t = 0; t < 1000U && (Xil_In32(CDMA_BASE + CDMACR) & CR_RESET); t++) {
        usleep(10);
    }
    Xil_Out32(CDMA_BASE + CDMACR, CR_IOC_EN | CR_ERR_EN);
    cdma_done = 0;

    XTime_GetTime(&t0);
    Xil_Out32(CDMA_BASE + CDMA_SA,     (u32)(UINTPTR)cdma_src);
    Xil_Out32(CDMA_BASE + CDMA_SA_MSB, (u32)((u64)(UINTPTR)cdma_src >> 32));
    Xil_Out32(CDMA_BASE + CDMA_DA,     (u32)(UINTPTR)cdma_dst);
    Xil_Out32(CDMA_BASE + CDMA_DA_MSB, (u32)((u64)(UINTPTR)cdma_dst >> 32));
    Xil_Out32(CDMA_BASE + CDMA_BTT,    CDMA_LEN);                /* starts the copy */
    for (t = 0; t < 100000U && !cdma_done; t++) {
        usleep(1);
    }
    XTime_GetTime(&t1);

    if (!cdma_done) {
        xil_printf("  no interrupt; status 0x%08lx\r\n", Xil_In32(CDMA_BASE + CDMASR));
        result("CDMA", 0);
        return;
    }
    Xil_DCacheInvalidateRange((UINTPTR)cdma_dst, CDMA_LEN);
    for (i = 0; i < CDMA_LEN; i++) {
        if (cdma_dst[i] != cdma_src[i]) {
            bad++;
        }
    }
    {
        u64 us = ((u64)(t1 - t0) * 1000000ULL) / COUNTS_PER_SECOND;
        xil_printf("  1 MB copied in %lu us (%lu MB/s incl. interrupt), status 0x%08lx, %lu bytes wrong\r\n",
                   (u32)us, us ? (u32)(1000000ULL / us) : 0U, cdma_sr, bad);
    }
    result("CDMA", bad == 0 && !(cdma_sr & SR_ERRS));
}
#endif
