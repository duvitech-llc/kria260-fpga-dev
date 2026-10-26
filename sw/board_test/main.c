/*
 * KV260 board test (bare metal, A53 #0, Vitis standalone BSP, SDT flow).
 *
 * Built by sw/create_vitis.py from output/kv260_base.xsa; loaded with
 *   xsdb tcl/program.tcl C:/kv260_ws/board_test/build/board_test.elf
 * Console: PS UART1 on the USB cable (J4, second FTDI port), 115200 8N1.
 *
 * Each test prints PASS, FAIL or SKIP, and is compiled in only when its
 * hardware is in the build (board_test.h):
 *   BRAM     8 KB PL scratch memory write/read-back                  always
 *   PMOD     8 pins driven and read back; jumpered pin pairs listed  pmod=1
 *   FAN      fan=ps: TTC0 PWM; fan=rtl: fabric PWM duty read back    always
 *   PL IRQ   axi_timer interrupts through the GIC, 100 per second    irq=1
 *   CDMA     PL DMA copies 1 MB in DDR through S_AXI_HP1_FPD, IRQ    dma=1
 *   DP       PL test pattern running, monitor found, link trained    dp=1
 *            (then the screen steps through colours; check by eye)
 *   CAM I2C  camera I2C switch, devices per channel, ISP and RPi IDs iic=1
 *   CAMERA   cam=rpi: IMX219 frames into DDR, test-pattern frames     cam=rpi
 *            identical, live frames different, ~30 frames/s
 *   MBV      MicroBlaze V co-processor: loaded by the A53, mailbox    cpu=mbv
 *            ping-pong with interrupts both ways, CRC-32 offload
 *   SD       PS SD1: card initialised, block 0 read (needs a card)   always
 *   I2C      PS I2C1 bus scan, SoM EEPROM at 0x50                     always
 *   ETH      PS GEM3: PHY found over MDIO, link state                always
 * Then it runs forever: a walking one on PMOD J2 (4 steps/s) and the fan
 * stepping 100 -> 75 -> 50 -> 25 % every 8 s, each change printed.
 */
#include "board_test.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xil_exception.h"
#include "xscugic.h"
#include "sleep.h"

static int fails;
static XScuGic gic;
static int gic_ready;

void result(const char *name, int ok)
{
    xil_printf("%-7s %s\r\n", name, ok ? "PASS" : "FAIL");
    if (!ok) {
        fails++;
    }
}

void skipped(const char *name, const char *why)
{
    xil_printf("%-7s SKIP (%s)\r\n", name, why);
}

int irq_setup(void)
{
    XScuGic_Config *cfg;

    if (gic_ready) {
        return XST_SUCCESS;
    }
    cfg = XScuGic_LookupConfig(XPAR_XSCUGIC_0_BASEADDR);
    if (cfg == NULL || XScuGic_CfgInitialize(&gic, cfg, cfg->CpuBaseAddress) != XST_SUCCESS) {
        return XST_FAILURE;
    }
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XScuGic_InterruptHandler, &gic);
    Xil_ExceptionEnable();
    gic_ready = 1;
    return XST_SUCCESS;
}

/* edge = 1: rising edge; 0: active-high level (the AXI IP interrupts). */
int irq_attach(u32 id, void (*handler)(void *), void *ref, int edge)
{
    if (irq_setup() != XST_SUCCESS) {
        return XST_FAILURE;
    }
    XScuGic_SetPriorityTriggerType(&gic, id, 0xA0, edge ? 0x3 : 0x1);
    if (XScuGic_Connect(&gic, id, (Xil_InterruptHandler)handler, ref) != XST_SUCCESS) {
        return XST_FAILURE;
    }
    XScuGic_Enable(&gic, id);
    return XST_SUCCESS;
}

int main(void)
{
    u32 walk = 0x01;

    xil_printf("\r\n==== KV260 board test ====\r\n");

    test_bram();
#ifdef HAVE_PMOD
    test_pmod();
    pmod_loopback_scan();
#else
    skipped("PMOD", "pmod=0");
#endif
    fan_start();
#ifdef HAVE_PL_TIMER
    test_pl_timer_irq();
#else
    skipped("PL IRQ", "irq=0");
#endif
#ifdef HAVE_CDMA
    test_cdma();
#else
    skipped("CDMA", "dma=0");
#endif
#ifdef HAVE_DP
    test_dp();
#else
    skipped("DP", "dp=0");
#endif
#ifdef HAVE_CAM_IIC
    test_cam_iic();
#else
    skipped("CAM I2C", "iic=0");
#endif
#if defined(HAVE_CAM_CAPTURE) && defined(HAVE_CAM_IIC)
    test_cam_capture();
#else
    skipped("CAMERA", "cam=none");
#endif
#ifdef HAVE_MBV
    test_mbv();
#else
    skipped("MBV", "cpu=none");
#endif
    test_ps_sd();
    test_ps_i2c();
    test_ps_eth_phy();

    xil_printf("==== %d failure(s) ====\r\n", fails);
#ifdef HAVE_DP
    dp_show();
#endif
    xil_printf("Running: PMOD walking one, fan 100/75/50/25 %% every 8 s\r\n");

    while (1) {
#ifdef HAVE_PMOD
        Xil_Out32(PMOD_BASE + GPIO_TRI, 0x00);
        Xil_Out32(PMOD_BASE + GPIO_DATA, walk);
#endif
        walk = ((walk << 1) | (walk >> 7)) & 0xFF;
        fan_tick();
        usleep(250000);
    }
    return 0;
}
