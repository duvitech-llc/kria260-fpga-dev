/*
 * KV260 board test: shared definitions.
 *
 * Every test is compiled in only when its hardware is in the build, decided
 * from xparameters.h (generated from the XSA). Base addresses fall back to
 * the fixed ones tcl/create_bd.tcl assigns.
 */
#ifndef BOARD_TEST_H
#define BOARD_TEST_H

#include "xparameters.h"
#include "xil_types.h"

/* ---- PL peripherals (M_AXI_HPM0_LPD) ------------------------------------- */
#if defined(XPAR_AXI_BRAM_CTRL_0_BASEADDR)
#define BRAM_BASE       XPAR_AXI_BRAM_CTRL_0_BASEADDR
#else
#define BRAM_BASE       0x80000000UL
#endif
#define BRAM_SIZE       0x2000U

#if defined(XPAR_AXI_GPIO_PMOD_BASEADDR)
#define HAVE_PMOD       1
#define PMOD_BASE       XPAR_AXI_GPIO_PMOD_BASEADDR
#endif

#if defined(XPAR_AXI_GPIO_FAN_BASEADDR)
#define HAVE_FAN_RTL    1
#define FAN_BASE        XPAR_AXI_GPIO_FAN_BASEADDR
#endif

#if defined(XPAR_AXI_TIMER_0_BASEADDR)
#define HAVE_PL_TIMER   1
#define PL_TIMER_BASE   XPAR_AXI_TIMER_0_BASEADDR
#endif

#if defined(XPAR_AXI_CDMA_0_BASEADDR)
#define HAVE_CDMA       1
#define CDMA_BASE       XPAR_AXI_CDMA_0_BASEADDR
#endif

#if defined(XPAR_AXI_GPIO_DP_BASEADDR)
#define HAVE_DP         1
#define DP_GPIO_BASE    XPAR_AXI_GPIO_DP_BASEADDR
/* dp_tpg control word: [1:0] pattern, [4] swap red/blue, [31:8] 0xRRGGBB */
#define DP_PAT_BARS     0x0U
#define DP_PAT_SOLID    0x1U
#define DP_PAT_BOX      0x2U
#define DP_PAT_RAMP     0x3U
#define DP_SWAP_RB      0x10U
#endif

#if defined(XPAR_AXI_IIC_CAM_BASEADDR) && defined(XPAR_AXI_GPIO_CAM_BASEADDR)
#define HAVE_CAM_IIC    1
#define CAM_IIC_BASE    XPAR_AXI_IIC_CAM_BASEADDR
#define CAM_GPIO_BASE   XPAR_AXI_GPIO_CAM_BASEADDR
#define CAM_AP1302_RST_B    0x1U
#define CAM_AP1302_STANDBY  0x2U
#define CAM_IAS_XSHUT_B     0x4U
#define CAM_RPI_EN          0x8U
#endif

#if defined(XPAR_MBV_MAILBOX_BASEADDR) || defined(XPAR_MAILBOX_0_BASEADDR) || defined(XPAR_MBV_BRAM_PS_BASEADDR)
#define HAVE_MBV        1
#define MBV_MEM_BASE    0x80100000UL    /* co-processor memory, 128 KB (its address 0) */
#define MBV_MBOX_BASE   0x800A0000UL    /* mailbox, PS side */
#define MBV_CTRL_BASE   0x800B0000UL    /* axi_gpio_mbv: bit 0 = run */
#endif

#if defined(XPAR_MIPI_CSI2_RX_0_BASEADDR) && defined(XPAR_V_FRMBUF_WR_0_BASEADDR)
#define HAVE_CAM_CAPTURE 1
#define CAM_CSI_BASE    XPAR_MIPI_CSI2_RX_0_BASEADDR
#define CAM_FB_BASE     XPAR_V_FRMBUF_WR_0_BASEADDR
#if defined(XPAR_MIPI_CSI2_RX_0_RX_CSI_LANES)
#define CAM_CSI_LANES   XPAR_MIPI_CSI2_RX_0_RX_CSI_LANES
#elif defined(XPAR_MIPI_CSI2_RX_0_CSI_LANES)
#define CAM_CSI_LANES   XPAR_MIPI_CSI2_RX_0_CSI_LANES
#else
#define CAM_CSI_LANES   2
#endif
#endif

/* PL -> PS interrupts: pl_ps_irq0[n] is GIC interrupt ID 121 + n
 * (tcl/create_bd.tcl assigns the bits). */
#define IRQ_PL(n)       (121U + (n))
#define IRQ_PL_TIMER    IRQ_PL(0)
#define IRQ_CDMA        IRQ_PL(1)
#define IRQ_CAM_IIC     IRQ_PL(2)
#define IRQ_MBV_MBOX    IRQ_PL(3)
#define IRQ_CAM_CSI     IRQ_PL(4)
#define IRQ_CAM_FB      IRQ_PL(5)

/* AXI GPIO registers (PG144) */
#define GPIO_DATA       0x0000U
#define GPIO_TRI        0x0004U     /* 1 = input */
#define GPIO2_DATA      0x0008U
#define GPIO2_TRI       0x000CU

/* ---- helpers (main.c) ----------------------------------------------------- */
void result(const char *name, int ok);
void skipped(const char *name, const char *why);
int  irq_setup(void);                                    /* GIC + exceptions */
int  irq_attach(u32 id, void (*handler)(void *), void *ref, int edge);

/* ---- tests ------------------------------------------------------------------ */
void test_bram(void);
void test_pmod(void);
void pmod_loopback_scan(void);
void fan_start(void);                 /* fan=ps: TTC0 PWM; fan=rtl: check fabric PWM */
void fan_tick(void);                  /* called every 250 ms from the main loop */
void test_pl_timer_irq(void);
void test_cdma(void);
void test_dp(void);
void dp_show(void);
void dp_set_pattern(u32 ctrl);
void test_cam_iic(void);
void cam_iic_init(void);
int  cam_iic_write(u8 addr, const u8 *data, int n);
int  cam_iic_read(u8 addr, u8 *data, int n);
int  cam_iic_read16(u8 addr, u16 reg, u8 *data, int n);
int  cam_iic_write16(u8 addr, u16 reg, const u8 *data, int n);
int  cam_iic_write16_long(u8 addr, u16 reg, const u8 *data, u32 n);
int  cam_mux_select(int ch);
void cam_ctrl(u32 bits);
void cam_power_up(void);
void test_mbv(void);
void test_cam_capture(void);
int  ap1302_start(void);
void test_ps_sd(void);
void test_ps_i2c(void);
void test_ps_eth_phy(void);

#endif
