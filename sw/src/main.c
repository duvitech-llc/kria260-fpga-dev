/*
 * KV260 bare-metal PL GPIO + fan PWM demo
 *
 * Target : psu_cortexa53_0, standalone BSP (Vitis Unified / SDT flow)
 * PL     : bitstream from this repo (tcl/create_bd.tcl)
 *
 * The block design assigns fixed AXI addresses on M_AXI_HPM0_LPD:
 *   0x8000_0000  BRAM (8 KB scratch)
 *   0x8001_0000  AXI GPIO 0 -> 8x PMOD J2 outputs
 *
 * Fan (carrier J13, pin A12 "fan_en_b"):
 *   Driven by PS TTC0 channel 0 waveform output, routed through EMIO
 *   to the PL pin (same as the official Kria base platforms).
 *   Carrier circuit is INVERTED: pin HIGH = fan OFF, pin LOW = fan ON.
 *   An unconfigured/idle pin means the fan runs - safe by default.
 *   PWM is ~100 Hz: the carrier drives the fan MOSFET gate through a
 *   10k pull-up (~5 us edges), so fast 25 kHz PWM would distort badly.
 */

#include "xil_io.h"
#include "xil_printf.h"
#include "sleep.h"
#include "xttcps.h"

#define PMOD_GPIO_BASE  0x80010000UL

/* AXI GPIO channel-1 register offsets (PG144) */
#define GPIO_DATA_OFF   0x0000U
#define GPIO_TRI_OFF    0x0004U

/* TTC0 channel 0 (ZynqMP fixed address) */
#define TTC0_CH0_BASE   0xFF110000UL

/* ~100 Hz PWM: 100 MHz LPD_LSBUS / 2^(5+1) prescale = 1.5625 MHz tick */
#define FAN_PRESCALE    5U
#define FAN_PERIOD      15625U

static XTtcPs FanTtc;

/*
 * With XTTCPS_OPTION_WAVE_POLARITY set, the wave output is HIGH from
 * interval start until the match value, then LOW until rollover.
 * fan_en_b is active-low, so high-time = (100 - percent) of the period.
 */
static void fan_set_percent(u32 percent)
{
    if (percent > 100U) {
        percent = 100U;
    }
    XTtcPs_SetMatchValue(&FanTtc, 0,
                         (u32)(((u64)FAN_PERIOD * (100U - percent)) / 100U));
}

static int fan_pwm_init(void)
{
    XTtcPs_Config *cfg;
    int status;

    cfg = XTtcPs_LookupConfig(TTC0_CH0_BASE);
    if (cfg == NULL) {
        return XST_FAILURE;
    }

    status = XTtcPs_CfgInitialize(&FanTtc, cfg, cfg->BaseAddress);
    if (status != XST_SUCCESS) {
        return status;
    }

    XTtcPs_SetOptions(&FanTtc,
                      XTTCPS_OPTION_INTERVAL_MODE |
                      XTTCPS_OPTION_MATCH_MODE |
                      XTTCPS_OPTION_WAVE_ENABLE |
                      XTTCPS_OPTION_WAVE_POLARITY);
    XTtcPs_SetPrescaler(&FanTtc, FAN_PRESCALE);
    XTtcPs_SetInterval(&FanTtc, FAN_PERIOD);
    fan_set_percent(100U);   /* full speed until told otherwise */
    XTtcPs_Start(&FanTtc);

    return XST_SUCCESS;
}

int main(void)
{
    static const u32 fan_steps[] = { 100U, 75U, 50U, 25U };
    u32 walk = 0x01;    /* walking one across the 8 PMOD pins */
    u32 tick = 0;
    u32 fan_idx = 0;

    xil_printf("\r\nKV260 bare-metal demo: PMOD GPIO + fan PWM\r\n");
    xil_printf("PMOD J2 @ 0x%08lx, fan on TTC0 ch0 wave out (A12)\r\n",
               PMOD_GPIO_BASE);

    /* PMOD: direction = output (no-op with C_ALL_OUTPUTS=1, kept for
       correctness if the core is ever rebuilt bidirectional) */
    Xil_Out32(PMOD_GPIO_BASE + GPIO_TRI_OFF, 0x00);

    if (fan_pwm_init() != XST_SUCCESS) {
        xil_printf("ERROR: fan TTC init failed\r\n");
    } else {
        xil_printf("Fan PWM running at ~100 Hz, %lu%%\r\n", fan_steps[0]);
    }

    while (1) {
        /* Walking one on PMOD J2, 4 steps/second */
        Xil_Out32(PMOD_GPIO_BASE + GPIO_DATA_OFF, walk);
        walk = ((walk << 1) | (walk >> 7)) & 0xFF;

        /* Step the fan speed every 8 seconds: 100 -> 75 -> 50 -> 25 -> ... */
        tick++;
        if ((tick % 32U) == 0U) {
            fan_idx = (fan_idx + 1U) % 4U;
            fan_set_percent(fan_steps[fan_idx]);
            xil_printf("Fan -> %lu%%\r\n", fan_steps[fan_idx]);
        }

        usleep(250000);
    }

    return 0;
}
