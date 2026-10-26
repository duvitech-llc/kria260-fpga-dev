/*
 * KV260 board test: AP1302 image signal processor (cam=isp, J7 IAS0 module).
 *
 * The AP1302 boots from firmware loaded over I2C (no flash on the module).
 * The firmware is AMD's, from the Ubuntu package linux-firmware-xilinx-ap1302;
 * `python -I sw/firmware/get_ap1302_fw.py` fetches it and writes
 * sw/board_test/ap1302_fw.h (git-ignored). Without that header this file
 * compiles to nothing and the ISP capture test is skipped.
 *
 * Sequence (as AMD's Linux driver drivers/media/i2c/ap1302.c does it):
 *   - reset, chip ID 0x0265 at register 0x0000
 *   - firmware = 4-byte header {u16 PLL-init size, u16 CRC} + bootdata;
 *     bootdata goes through the 8 KB window at register 0x8000:
 *       clear CRC (0xF052) -> PLL-init part -> BOOTDATA_STAGE (0x6002) = 2,
 *       1 ms -> rest -> 40 ms -> CRC must match -> BOOTDATA_STAGE = 0xFFFF
 *   - stall, MIPI clock timing tweak, 1920x1080 YUV 4:2:2 on 4 lanes,
 *     un-stall: frames start
 */
#include "board_test.h"

#if defined(HAVE_CAM_IIC) && defined(__has_include)
#if __has_include("ap1302_fw.h")
#define HAVE_AP1302_FW 1
#endif
#endif

#ifdef HAVE_AP1302_FW
#include "xil_printf.h"
#include "sleep.h"
#include "ap1302_fw.h"

#define AP1302_ADDR             0x3C
#define AP1302_CHIP_ID          0x0000
#define AP1302_PREVIEW_WIDTH    0x2000
#define AP1302_PREVIEW_HEIGHT   0x2002
#define AP1302_PREVIEW_OUT_FMT  0x2012
#define AP1302_PREVIEW_HINF     0x2030
#define AP1302_BOOTDATA_STAGE   0x6002
#define AP1302_SYS_START        0x601A
#define AP1302_ADVANCED_BASE    0xF038      /* 32-bit: page of the advanced registers */
#define AP1302_SIP_CRC          0xF052
#define AP1302_ADV_START        0xE000      /* advanced registers appear here */
#define AP1302_FW_WINDOW        0x8000
#define AP1302_FW_WINDOW_SIZE   0x2000
#define AP1302_CHUNK            256U

static int w16(u16 reg, u16 v)
{
    u8 b[2] = { (u8)(v >> 8), (u8)v };
    return cam_iic_write16(AP1302_ADDR, reg, b, 2);
}

static int w32(u16 reg, u32 v)
{
    u8 b[4] = { (u8)(v >> 24), (u8)(v >> 16), (u8)(v >> 8), (u8)v };
    return cam_iic_write16(AP1302_ADDR, reg, b, 4);
}

static int r16(u16 reg, u16 *v)
{
    u8 b[2];
    int e = cam_iic_read16(AP1302_ADDR, reg, b, 2);
    *v = (u16)((b[0] << 8) | b[1]);
    return e;
}

static int r32(u16 reg, u32 *v)
{
    u8 b[4];
    int e = cam_iic_read16(AP1302_ADDR, reg, b, 4);
    *v = ((u32)b[0] << 24) | ((u32)b[1] << 16) | ((u32)b[2] << 8) | b[3];
    return e;
}

/* Advanced registers: 0x00PPRRRR = page PP, register RRRR (32-bit). */
static int adv_write(u32 reg, u32 v)
{
    return w32(AP1302_ADVANCED_BASE, reg & 0x00FF0000U) |
           w32((u16)(AP1302_ADV_START + (reg & 0xFFFFU)), v);
}

static int adv_read(u32 reg, u32 *v)
{
    return w32(AP1302_ADVANCED_BASE, reg & 0x00FF0000U) |
           r32((u16)(AP1302_ADV_START + (reg & 0xFFFFU)), v);
}

static unsigned int win_pos;

static int write_window(const u8 *p, u32 n)
{
    while (n) {
        u32 size = AP1302_FW_WINDOW_SIZE - win_pos;

        if (size > n) {
            size = n;
        }
        if (size > AP1302_CHUNK) {
            size = AP1302_CHUNK;
        }
        if (cam_iic_write16_long(AP1302_ADDR, (u16)(AP1302_FW_WINDOW + win_pos), p, size) != 0) {
            return -1;
        }
        p += size;
        n -= size;
        win_pos = (win_pos + size) % AP1302_FW_WINDOW_SIZE;
    }
    return 0;
}

/* Boot the AP1302 and leave it streaming 1920x1080 YUV 4:2:2 on 4 lanes.
 * Returns 0 on success. */
int ap1302_start(void)
{
    const u32 pll = (u32)ap1302_fw[0] | ((u32)ap1302_fw[1] << 8);
    const u16 crc_want = (u16)(ap1302_fw[2] | (ap1302_fw[3] << 8));
    const u8 *boot = &ap1302_fw[4];
    const u32 boot_len = AP1302_FW_SIZE - 4U;
    u16 id, crc;
    u32 t3;

    /* Reset with the sensor powered; standby off. */
    cam_ctrl(CAM_RPI_EN | CAM_IAS_XSHUT_B);
    usleep(10000);
    cam_ctrl(CAM_RPI_EN | CAM_IAS_XSHUT_B | CAM_AP1302_RST_B);
    usleep(20000);
    cam_mux_select(0);
    if (r16(AP1302_CHIP_ID, &id) != 0 || id != 0x0265) {
        xil_printf("  AP1302 not found (ID 0x%04x)\r\n", id);
        return -1;
    }

    xil_printf("  loading AP1302 firmware: %u bytes, PLL part %lu, CRC 0x%04x\r\n",
               AP1302_FW_SIZE, pll, crc_want);
    win_pos = 0;
    if (w16(AP1302_SIP_CRC, 0xFFFF) || write_window(boot, pll) ||
        w16(AP1302_BOOTDATA_STAGE, 0x0002)) {
        xil_printf("  I2C error during the PLL part\r\n");
        return -1;
    }
    usleep(2000);
    if (write_window(boot + pll, boot_len - pll)) {
        xil_printf("  I2C error during the firmware download\r\n");
        return -1;
    }
    usleep(40000);
    if (r16(AP1302_SIP_CRC, &crc) || crc != crc_want) {
        xil_printf("  firmware CRC 0x%04x, expected 0x%04x\r\n", crc, crc_want);
        return -1;
    }
    w16(AP1302_BOOTDATA_STAGE, 0xFFFF);
    xil_printf("  firmware CRC 0x%04x matches; AP1302 running\r\n", crc);

    /* Stall, configure the output, un-stall. */
    w16(AP1302_SYS_START, 0x8040);              /* PLL lock, stall mode "disabled" */
    w16(AP1302_SYS_START, 0x8140);              /* + stall enable */
    usleep(200000);
    adv_write(0x00230000U, 0xC8U);              /* IRQ_SYS_INTE: SIPM | SIPS FIFO write */
    if (adv_read(0x00840014U, &t3) == 0) {      /* HINF_MIPI_T3: Tclk-post + 5, Tclk-pre + 1 */
        u32 post = (t3 & 0xFFU) + 5U, pre = ((t3 >> 8) & 0xFFU) + 1U;
        adv_write(0x00840014U, (t3 & ~0xFFFFU) | (pre << 8) | post);
    }
    w16(AP1302_PREVIEW_HINF, (1U << 4) | 4U);   /* spoof frame, 4 MIPI lanes */
    w16(AP1302_PREVIEW_WIDTH, 1920);
    w16(AP1302_PREVIEW_HEIGHT, 1080);
    w16(AP1302_PREVIEW_OUT_FMT, (5U << 4) | 0U); /* YUV (JFIF), 4:2:2 */
    w16(AP1302_SYS_START, 0x8340);              /* un-stall: stream */
    cam_mux_select(-1);
    return 0;
}
#else
int ap1302_start(void)
{
    return -2;      /* firmware header not generated */
}
#endif
