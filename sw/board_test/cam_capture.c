/*
 * KV260 board test: MIPI camera capture into DDR (cam=rpi, and the shared
 * part of cam=ias / cam=isp).
 *
 * Path: sensor -> MIPI CSI-2 receiver (mipi_csi2_rx_0) -> 8-bit remap ->
 * frame buffer writer (v_frmbuf_wr_0) -> S_AXI_HP0_FPD -> DDR at CAM_FB_ADDR.
 *
 * cam=rpi: Raspberry Pi camera v2 (Sony IMX219) on J9, 2 lanes at 912 Mb/s,
 * 1920x1080 RAW10 cropped from the centre, ~30 frames per second; register
 * settings from the Linux imx219 driver. The frame buffer keeps the 8 most
 * significant bits of each Bayer sample (one byte per pixel).
 *
 * Checks:
 *   - frames arrive (frame buffer "done" interrupts, ~30 per second)
 *   - with the sensor's colour-bar test pattern, two different frames are
 *     identical (CRC over the whole frame)
 *   - with the live image, frames differ (noise)
 * The last live frame stays in DDR; print_dump_hint() says how to copy it to
 * the PC with xsdb.
 */
#include "board_test.h"

#if defined(HAVE_CAM_CAPTURE) && defined(HAVE_CAM_IIC)
#include <string.h>
#include "xil_io.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "sleep.h"
#include "xcsiss.h"
#include "xv_frmbufwr_l2.h"

#define CAM_W           1920U
#define CAM_H           1080U
#define CAM_FB_ADDR     0x30000000UL        /* 2 MB, outside the program */

static XCsiSs          csi;
static XV_FrmbufWr_l2  fb;
static volatile u32    frames;

/* ---- IMX219 (Linux drivers/media/i2c/imx219.c) ------------------------- */
#define IMX219_ADDR     0x10

static int w8(u16 reg, u8 v)
{
    return cam_iic_write16(IMX219_ADDR, reg, &v, 1);
}

static int w16(u16 reg, u16 v)
{
    u8 b[2] = { (u8)(v >> 8), (u8)v };
    return cam_iic_write16(IMX219_ADDR, reg, b, 2);
}

static int imx219_setup(int test_pattern)
{
    static const struct { u16 reg; u8 val; } common[] = {
        { 0x0100, 0x00 },                                   /* standby */
        { 0x30eb, 0x05 }, { 0x30eb, 0x0c }, { 0x300a, 0xff }, { 0x300b, 0xff },
        { 0x30eb, 0x05 }, { 0x30eb, 0x09 },                 /* unlock 0x3000.. */
        { 0x455e, 0x00 }, { 0x471e, 0x4b }, { 0x4767, 0x0f }, { 0x4750, 0x14 },
        { 0x4540, 0x00 }, { 0x47b4, 0x14 }, { 0x4713, 0x30 }, { 0x478b, 0x10 },
        { 0x478f, 0x10 }, { 0x4793, 0x10 }, { 0x4797, 0x0e }, { 0x479b, 0x0e },
        { 0x0170, 0x01 }, { 0x0171, 0x01 },                 /* x/y odd increment */
        { 0x0128, 0x00 },                                   /* D-PHY timing auto */
        /* 2-lane PLL: 24 MHz in, 912 Mb/s per lane */
        { 0x0301, 0x05 }, { 0x0303, 0x01 }, { 0x0304, 0x03 }, { 0x0305, 0x03 },
        { 0x030b, 0x01 }, { 0x0114, 0x01 },                 /* 2 lanes */
        { 0x0174, 0x00 }, { 0x0175, 0x00 },                 /* no binning */
        { 0x0172, 0x00 },                                   /* orientation */
        { 0x0309, 0x0a },                                   /* 10 bits per pixel */
        { 0x0157, 0x80 },                                   /* analogue gain */
    };
    /* 1920x1080 from the centre of the 3296x2480 array (8,8 = first pixel) */
    const u16 x0 = (3296U - CAM_W) / 2U - 8U, y0 = (2480U - CAM_H) / 2U - 8U;
    u32 i;
    int err = 0;

    for (i = 0; i < sizeof(common) / sizeof(common[0]); i++) {
        err |= w8(common[i].reg, common[i].val);
    }
    err |= w16(0x012a, 24U * 256U);         /* EXCK 24 MHz */
    err |= w16(0x0306, 57);                 /* PLL VT multiplier */
    err |= w16(0x030c, 114);                /* PLL OP multiplier */
    err |= w16(0x0164, x0);
    err |= w16(0x0166, x0 + CAM_W - 1U);
    err |= w16(0x0168, y0);
    err |= w16(0x016a, y0 + CAM_H - 1U);
    err |= w16(0x016c, CAM_W);
    err |= w16(0x016e, CAM_H);
    err |= w16(0x0624, CAM_W);              /* test pattern window */
    err |= w16(0x0626, CAM_H);
    err |= w16(0x018c, 0x0a0a);             /* RAW10 */
    err |= w16(0x0160, 1763);               /* frame length: ~30 fps */
    err |= w16(0x0162, 0x0d78);             /* line length */
    err |= w16(0x015a, 1600);               /* exposure, lines */
    err |= w16(0x0158, 0x0100);             /* digital gain 1.0 */
    err |= w16(0x0600, test_pattern ? 2U : 0U);   /* 2 = colour bars */
    err |= w8(0x0100, 0x01);                /* streaming */
    return err;
}

/* ---- capture path ---------------------------------------------------------- */
/* Frame written. In interrupt mode the driver turns the core's auto-restart
 * off, so each frame is started from here (found on the board: without it
 * exactly one frame was captured). */
static void fb_done(void *ref)
{
    frames++;
    XVFrmbufWr_Start((XV_FrmbufWr_l2 *)ref);
}

static u32 frame_crc(void)
{
    const volatile u32 *p = (const volatile u32 *)CAM_FB_ADDR;
    u32 i, c = 0x12345678U;

    /* the first W x H bytes: a whole Y8 frame, the top half of a YUYV one */
    Xil_DCacheInvalidateRange(CAM_FB_ADDR, CAM_W * CAM_H);
    for (i = 0; i < CAM_W * CAM_H / 4U; i++) {
        c = (c << 5) ^ (c >> 27) ^ p[i];
    }
    return c;
}

static int capture_start(XVidC_ColorFormat mem, XVidC_ColorFormat strm, u32 stride)
{
    XCsiSs_Config *ccfg = XCsiSs_LookupConfig(CAM_CSI_BASE);
    XVidC_VideoStream s;

    if (ccfg == NULL || XCsiSs_CfgInitialize(&csi, ccfg, ccfg->BaseAddr) != XST_SUCCESS) {
        xil_printf("  CSI-2 receiver: no configuration\r\n");
        return -1;
    }
    xil_printf("  CSI-2 receiver found, %d lanes\r\n", CAM_CSI_LANES);
    XCsiSs_Configure(&csi, CAM_CSI_LANES, 0);
    XCsiSs_Activate(&csi, XCSI_ENABLE);

    if (XVFrmbufWr_Initialize(&fb, CAM_FB_BASE) != XST_SUCCESS) {
        xil_printf("  frame buffer writer: no configuration\r\n");
        return -1;
    }
    memset(&s, 0, sizeof(s));
    s.ColorFormatId = strm;
    s.ColorDepth    = XVIDC_BPC_8;
    s.PixPerClk     = XVIDC_PPC_1;
    s.Timing.HActive = CAM_W;
    s.Timing.VActive = CAM_H;
    if (XVFrmbufWr_SetMemFormat(&fb, stride, mem, &s) != XST_SUCCESS ||
        XVFrmbufWr_SetBufferAddr(&fb, CAM_FB_ADDR) != XST_SUCCESS) {
        xil_printf("  frame buffer writer: format not accepted\r\n");
        return -1;
    }
    /* The driver asserts a non-NULL callback reference (an assertion
     * failure hangs the program): pass the instance. */
    XVFrmbufWr_SetCallback(&fb, XVFRMBUFWR_HANDLER_DONE, (void *)fb_done, &fb);
    if (irq_attach(IRQ_CAM_FB, XVFrmbufWr_InterruptHandler, &fb, 0) != XST_SUCCESS) {
        return -1;
    }
    XVFrmbufWr_InterruptEnable(&fb, XVFRMBUFWR_IRQ_DONE_MASK);
    XVFrmbufWr_Start(&fb);
    xil_printf("  frame buffer writer started at 0x%08lx\r\n", (u32)CAM_FB_ADDR);
    return 0;
}

/* CSI-2 receiver registers (PG232): controller at the base, D-PHY at +0x1000. */
static void csi_dump(void)
{
    static const struct { u32 off; const char *name; } r[] = {
        { 0x00, "core config" }, { 0x04, "protocol config" }, { 0x10, "core status" },
        { 0x24, "interrupt status" }, { 0x30, "generic short packet" },
        { 0x3C, "clock lane info" }, { 0x40, "lane 0 info" }, { 0x44, "lane 1 info" },
        { 0x48, "lane 2 info" }, { 0x4C, "lane 3 info" },
        { 0x60, "VC0 image info 1 (lines, bytes)" }, { 0x64, "VC0 image info 2 (data type)" },
        { 0x1000, "D-PHY control" }, { 0x1008, "D-PHY init" }, { 0x1018, "D-PHY HS timeout" },
        { 0x1024, "D-PHY status" }, { 0x1030, "D-PHY clock lane status" },
        { 0x1040, "D-PHY lane 0 status" }, { 0x1044, "D-PHY lane 1 status" },
        { 0x1048, "D-PHY lane 2 status" }, { 0x104C, "D-PHY lane 3 status" },
    };
    u32 i;

    for (i = 0; i < sizeof(r) / sizeof(r[0]); i++) {
        xil_printf("    CSI +0x%04lx %-32s 0x%08lx\r\n", r[i].off, r[i].name, Xil_In32(CAM_CSI_BASE + r[i].off));
    }
    xil_printf("    frame buffer control 0x%08lx\r\n", Xil_In32(CAM_FB_BASE));
}

static u32 count_frames(u32 ms)
{
    u32 f0 = frames;
    usleep(ms * 1000U);
    return frames - f0;
}

/* cam=isp: AP1302 (cam_isp.c) -> 4 lanes YUV 4:2:2 -> frame buffer YUYV. */
static void test_isp_capture(void)
{
    int r;
    u32 n, c1, c2;

    memset((void *)CAM_FB_ADDR, 0, CAM_W * CAM_H * 2U);
    Xil_DCacheFlushRange(CAM_FB_ADDR, CAM_W * CAM_H * 2U);
    if (capture_start(XVIDC_CSF_MEM_YUYV8, XVIDC_CSF_YCRCB_422, CAM_W * 2U) != 0) {
        result("CAMERA", 0);
        return;
    }
    r = ap1302_start();
    if (r == -2) {
        skipped("CAMERA", "AP1302 firmware missing: run python -I sw/firmware/get_ap1302_fw.py, rebuild");
        return;
    }
    if (r != 0) {
        result("CAMERA", 0);
        return;
    }
    usleep(500000);
    n = count_frames(1000);
    c1 = frame_crc();
    count_frames(100);
    c2 = frame_crc();
    xil_printf("  AP1302 1920x1080 YUV 4:2:2: %lu frames in 1 s, CRCs 0x%08lx 0x%08lx\r\n", n, c1, c2);
    if (n == 0U) {
        csi_dump();
    }
    result("CAMERA", n >= 10U && c1 != c2);
    xil_printf("  last frame: %u x %u YUYV (2 bytes per pixel) at 0x%08lx; copy it with\r\n",
               CAM_W, CAM_H, (u32)CAM_FB_ADDR);
    xil_printf("    xsdb: connect; targets -set -filter {name =~ \"*A53*#0\"}; mrd -bin -file frame.yuv 0x%08lx %u\r\n",
               (u32)CAM_FB_ADDR, CAM_W * CAM_H / 2U);
}

void test_cam_capture(void)
{
    u8 b[2];
    u32 n, c1, c2;

    if (CAM_CSI_LANES == 4) {
        cam_power_up();
        cam_mux_select(0);
        if (cam_iic_read16(0x3C, 0x0000, b, 2) == 0 && ((b[0] << 8) | b[1]) == 0x0265) {
            test_isp_capture();
        } else {
            skipped("CAMERA", "4-lane build without an AP1302 (cam=ias start-up is not written yet)");
        }
        return;
    }

    cam_power_up();
    cam_mux_select(2);
    if (cam_iic_read16(IMX219_ADDR, 0x0000, b, 2) != 0 || ((b[0] << 8) | b[1]) != 0x0219) {
        skipped("CAMERA", "no IMX219 (RPi camera v2) on J9");
        return;
    }
    memset((void *)CAM_FB_ADDR, 0, CAM_W * CAM_H);
    Xil_DCacheFlushRange(CAM_FB_ADDR, CAM_W * CAM_H);
    if (capture_start(XVIDC_CSF_MEM_Y8, XVIDC_CSF_YONLY, CAM_W) != 0) {
        result("CAMERA", 0);
        return;
    }
    if (imx219_setup(1) != 0) {
        xil_printf("  IMX219 register writes failed\r\n");
        result("CAMERA", 0);
        return;
    }
    usleep(300000);
    n = count_frames(1000);
    xil_printf("  IMX219 1920x1080 RAW10 colour bars: %lu frames in 1 s\r\n", n);
    if (n < 25U) {
        csi_dump();
        result("CAMERA", 0);
        return;
    }
    c1 = frame_crc();
    count_frames(100);
    c2 = frame_crc();
    xil_printf("  test pattern frame CRC 0x%08lx, a later frame 0x%08lx (must match)\r\n", c1, c2);

    w8(0x0100, 0x00);
    w16(0x0600, 0);                         /* live image */
    w8(0x0100, 0x01);
    usleep(300000);
    n = count_frames(1000);
    {
        u32 l1 = frame_crc(), l2;
        count_frames(100);
        l2 = frame_crc();
        xil_printf("  live image: %lu frames in 1 s, CRCs 0x%08lx 0x%08lx (expected to differ)\r\n", n, l1, l2);
        result("CAMERA", c1 == c2 && n >= 25U && l1 != l2);
    }
    xil_printf("  last frame: %u x %u, 1 byte per pixel (8-bit Bayer RGGB), at 0x%08lx; copy it with\r\n",
               CAM_W, CAM_H, (u32)CAM_FB_ADDR);
    xil_printf("    xsdb: connect; targets -set -filter {name =~ \"*A53*#0\"}; mrd -bin -file frame.raw 0x%08lx %u\r\n",
               (u32)CAM_FB_ADDR, CAM_W * CAM_H / 4U);
}
#endif
