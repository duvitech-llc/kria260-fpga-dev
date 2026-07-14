/*
 * KV260 bare-metal PL GPIO demo
 *
 * Target : psu_cortexa53_0, standalone BSP (Vitis 2025.2)
 * PL     : bitstream from this repo (tcl/create_bd.tcl)
 *
 * The block design assigns fixed AXI addresses on M_AXI_HPM0_LPD:
 *   0x8000_0000  BRAM (8 KB scratch)
 *   0x8001_0000  AXI GPIO 0 -> 4x carrier LEDs (DS5-DS8, active-high)
 *   0x8002_0000  AXI GPIO 1 -> 8x PMOD J2 outputs
 *
 * Both AXI GPIO cores are compiled with C_ALL_OUTPUTS=1, so the
 * tri-state register is a no-op in hardware; it is still written
 * below so the code stays correct if the cores are ever rebuilt
 * as bidirectional.
 */

#include "xil_io.h"
#include "xil_printf.h"
#include "sleep.h"

#define LED_GPIO_BASE   0x80010000UL
#define PMOD_GPIO_BASE  0x80020000UL

/* AXI GPIO channel-1 register offsets (PG144) */
#define GPIO_DATA_OFF   0x0000U
#define GPIO_TRI_OFF    0x0004U

int main(void)
{
    xil_printf("\r\nKV260 bare-metal PL GPIO demo\r\n");
    xil_printf("PMOD J2 @ 0x%08lx, LEDs @ 0x%08lx\r\n",
               PMOD_GPIO_BASE, LED_GPIO_BASE);

    /* Direction: 0 = output */
    Xil_Out32(PMOD_GPIO_BASE + GPIO_TRI_OFF, 0x00);
    Xil_Out32(LED_GPIO_BASE  + GPIO_TRI_OFF, 0x0);

    u32 walk  = 0x01;   /* walking one across the 8 PMOD pins */
    u32 count = 0;      /* binary count on the 4 LEDs */

    while (1) {
        Xil_Out32(PMOD_GPIO_BASE + GPIO_DATA_OFF, walk);
        Xil_Out32(LED_GPIO_BASE  + GPIO_DATA_OFF, count & 0xF);

        walk = ((walk << 1) | (walk >> 7)) & 0xFF;
        count++;

        usleep(250000);
    }

    return 0;
}
