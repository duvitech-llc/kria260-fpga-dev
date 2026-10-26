/*
 * KV260 board test: DisplayPort live video from the PL (dp=1).
 *
 * The PL test pattern (src/rtl/video/dp_tpg.v) feeds the PS DisplayPort
 * controller's live-video input. This file trains the DP link to the monitor
 * (J6 DisplayPort, or J5 HDMI through the carrier's converter), selects the
 * live input with a PL video clock, and sets the 1280x720 at 60 Hz stream.
 * The pattern itself is chosen through axi_gpio_dp.
 *
 * Checks: a monitor is connected (hot plug), the link trains, and the PL
 * frame counter advances at ~60 frames per second. Whether the picture is
 * right is for a person to see; dp_show() steps through colours and prints
 * what should be on the screen.
 */
#include "board_test.h"

#ifdef HAVE_DP
#include "xil_io.h"
#include "xil_printf.h"
#include "sleep.h"
#include "xdppsu.h"
#include "xavbuf.h"

static XDpPsu  dp;
static XAVBuf  avbuf;
static int     dp_up;

static u32 dp_frames(void)
{
    return Xil_In32(DP_GPIO_BASE + GPIO2_DATA) & 0xFFFFU;
}

void dp_set_pattern(u32 ctrl)
{
    Xil_Out32(DP_GPIO_BASE + GPIO_DATA, ctrl);
}

static int dp_train(void)
{
    u32 t;

    for (t = 0; t < 50U && !XDpPsu_IsConnected(&dp); t++) {
        usleep(100000);
    }
    if (!XDpPsu_IsConnected(&dp)) {
        xil_printf("  no monitor detected (hot plug) on J6/J5\r\n");
        return XST_FAILURE;
    }
    if (XDpPsu_GetRxCapabilities(&dp) != XST_SUCCESS) {
        xil_printf("  could not read the monitor's DP capabilities (AUX)\r\n");
        return XST_FAILURE;
    }
    XDpPsu_SetEnhancedFrameMode(&dp, 1);
    XDpPsu_SetDownspread(&dp, 0);
    if (XDpPsu_CfgMainLinkMax(&dp) != XST_SUCCESS) {
        return XST_FAILURE;
    }
    if (XDpPsu_EstablishLink(&dp) != XST_SUCCESS) {
        xil_printf("  link training failed\r\n");
        return XST_FAILURE;
    }
    xil_printf("  link trained: %d lane(s) at %d Mb/s per lane\r\n",
               dp.LinkConfig.LaneCount, 270 * dp.LinkConfig.LinkRate);
    return XST_SUCCESS;
}

static void dp_stream(void)
{
    /* PL live video in, RGB 8 bits per component, clocked by the PL. The
     * video clock (VPLL) is already 74.25 MHz from psu_init; the driver's
     * XAVBuf_SetPixelClock() is not used, it assumes another PLL reference. */
    XAVBuf_InputVideoSelect(&avbuf, XAVBUF_VIDSTREAM1_LIVE, XAVBUF_VIDSTREAM2_NONE);
    XAVBuf_SetInputLiveVideoFormat(&avbuf, RGB_8BPC);
    XAVBuf_SetOutputVideoFormat(&avbuf, RGB_8BPC);
    XAVBuf_ConfigureVideoPipeline(&avbuf);
    XAVBuf_ConfigureOutputVideo(&avbuf);
    XAVBuf_SetBlenderAlpha(&avbuf, 0, 0);
    XAVBuf_SetAudioVideoClkSrc(&avbuf, XAVBUF_PL_CLK, XAVBUF_PS_CLK);
    XAVBuf_SoftReset(&avbuf);

    XDpPsu_CfgMsaSetBpc(&dp, 8);
    XDpPsu_CfgMsaEnSynchClkMode(&dp, 1);
    XDpPsu_CfgMsaUseStandardVideoMode(&dp, XVIDC_VM_1280x720_60_P);
    XDpPsu_EnableMainLink(&dp, 0);
    XDpPsu_WriteReg(dp.Config.BaseAddr, XDPPSU_SOFT_RESET, 0x1);
    XDpPsu_WriteReg(dp.Config.BaseAddr, XDPPSU_SOFT_RESET, 0x0);
    XDpPsu_SetVideoMode(&dp);
    XDpPsu_EnableMainLink(&dp, 1);
}

void test_dp(void)
{
    XDpPsu_Config *cfg = XDpPsu_LookupConfig(XPAR_XDPPSU_0_BASEADDR);
    u32 f0, f1;

    dp_set_pattern(DP_PAT_BARS);
    f0 = dp_frames();
    usleep(500000);
    f1 = dp_frames();
    xil_printf("  PL pattern: %lu frames in 0.5 s (expect 30)\r\n", (f1 - f0) & 0xFFFFU);
    if (((f1 - f0) & 0xFFFFU) < 28U || ((f1 - f0) & 0xFFFFU) > 32U) {
        xil_printf("  the PS video clock (dp_video_ref_clk) is not 74.25 MHz\r\n");
        result("DP", 0);
        return;
    }

    if (cfg == NULL) {
        result("DP", 0);
        return;
    }
    XDpPsu_CfgInitialize(&dp, cfg, cfg->BaseAddr);
    XAVBuf_CfgInitialize(&avbuf, dp.Config.BaseAddr);
    if (XDpPsu_InitializeTx(&dp) != XST_SUCCESS) {
        xil_printf("  DP transmitter did not initialise\r\n");
        result("DP", 0);
        return;
    }
    if (dp_train() != XST_SUCCESS) {
        result("DP", 0);
        return;
    }
    dp_stream();
    f0 = dp_frames();
    usleep(500000);
    f1 = dp_frames();
    xil_printf("  streaming 1280x720; PL pattern still at %lu frames in 0.5 s\r\n", (f1 - f0) & 0xFFFFU);
    dp_up = 1;
    result("DP", ((f1 - f0) & 0xFFFFU) >= 28U && ((f1 - f0) & 0xFFFFU) <= 32U);
}

/* Step through the patterns; prints what the monitor should show. */
void dp_show(void)
{
    static const struct { u32 ctrl; const char *what; } step[] = {
        { DP_PAT_SOLID | 0xFF000000U, "solid RED"   },
        { DP_PAT_SOLID | 0x00FF0000U, "solid GREEN" },
        { DP_PAT_SOLID | 0x0000FF00U, "solid BLUE"  },
        { DP_PAT_BARS,                "colour bars: white yellow cyan green magenta red blue black" },
        { DP_PAT_RAMP,                "grey ramp, dark on the left" },
        { DP_PAT_BOX,                 "colour bars with a white square bouncing around" },
    };
    u32 i;

    if (!dp_up) {
        return;
    }
    for (i = 0; i < sizeof(step) / sizeof(step[0]); i++) {
        dp_set_pattern(step[i].ctrl);
        xil_printf("DP: monitor should now show %s\r\n", step[i].what);
        sleep(3);
    }
}
#endif
