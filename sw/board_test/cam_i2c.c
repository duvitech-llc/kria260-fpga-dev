/*
 * KV260 board test: camera I2C and camera control pins (iic=1).
 *
 * The PL I2C master (axi_iic_cam, used here through its registers, PG090)
 * reaches the cameras through a TCA9546 switch on the carrier:
 *   channel 0  AP1302 ISP (J7 IAS0 module behind it)    ISP at 0x3C
 *   channel 1  IAS1 sensor (J8)
 *   channel 2  Raspberry Pi camera (J9)                  IMX219 at 0x10
 * The control pins come from axi_gpio_cam (bit 0 ap1302_rst_b, 1
 * ap1302_standby, 2 ias_xshutdown_b, 3 rpi_cam_en).
 *
 * The test powers the three camera paths up, finds the switch, lists what
 * answers on each channel and reads the chip IDs it knows. It only reads
 * from the cameras.
 */
#include "board_test.h"

#ifdef HAVE_CAM_IIC
#include "xil_io.h"
#include "xil_printf.h"
#include "sleep.h"

/* ---- AXI IIC, dynamic controller mode ----------------------------------- */
#define IIC_ISR     (CAM_IIC_BASE + 0x020)
#define IIC_SOFTR   (CAM_IIC_BASE + 0x040)
#define IIC_CR      (CAM_IIC_BASE + 0x100)
#define IIC_SR      (CAM_IIC_BASE + 0x104)
#define IIC_TX      (CAM_IIC_BASE + 0x108)
#define IIC_RX      (CAM_IIC_BASE + 0x10C)
#define IIC_PIRQ    (CAM_IIC_BASE + 0x120)
#define IIC_START   0x100U
#define IIC_STOP    0x200U
#define SR_BB       0x04U
#define SR_RXEMPTY  0x40U
#define SR_TXEMPTY  0x80U
#define ISR_ARB     0x01U
#define ISR_NACK    0x02U   /* also set at the end of every read (the
                               controller's own final NACK): an error only
                               while writing */

static u8 mux_addr;         /* 0 = switch not found */

void cam_iic_init(void)
{
    Xil_Out32(IIC_SOFTR, 0xA);
    Xil_Out32(IIC_PIRQ, 0x0F);
    Xil_Out32(IIC_CR, 0x2);
    Xil_Out32(IIC_CR, 0x1);
    Xil_Out32(IIC_ISR, Xil_In32(IIC_ISR));
}

static int iic_wait_idle(u32 errors)
{
    int t;

    for (t = 0; t < 2000; t++) {            /* up to 100 ms */
        u32 sr = Xil_In32(IIC_SR);

        if (Xil_In32(IIC_ISR) & errors) {
            break;
        }
        if (t >= 4 && (sr & SR_TXEMPTY) && !(sr & SR_BB)) {
            return 0;
        }
        usleep(50);
    }
    cam_iic_init();                         /* releases the bus after an error */
    return -1;
}

static int iic_rx(u8 *data, int n)
{
    int i, t;

    for (i = 0; i < n; i++) {
        for (t = 0; t < 2000; t++) {
            if (!(Xil_In32(IIC_SR) & SR_RXEMPTY)) {
                break;
            }
            if (Xil_In32(IIC_ISR) & ISR_ARB) {
                t = 2000;
            }
            usleep(50);
        }
        if (t >= 2000) {
            cam_iic_init();
            return -1;
        }
        data[i] = (u8)Xil_In32(IIC_RX);
    }
    return iic_wait_idle(ISR_ARB);
}

/* Write n bytes (n >= 1) to device addr. */
int cam_iic_write(u8 addr, const u8 *data, int n)
{
    int i;

    Xil_Out32(IIC_ISR, Xil_In32(IIC_ISR));
    Xil_Out32(IIC_TX, IIC_START | ((u32)addr << 1));
    for (i = 0; i < n; i++) {
        Xil_Out32(IIC_TX, data[i] | (i == n - 1 ? IIC_STOP : 0U));
    }
    return iic_wait_idle(ISR_ARB | ISR_NACK);
}

/* Read n bytes (1..15) from device addr, no register address. */
int cam_iic_read(u8 addr, u8 *data, int n)
{
    Xil_Out32(IIC_ISR, Xil_In32(IIC_ISR));
    Xil_Out32(IIC_TX, IIC_START | ((u32)addr << 1) | 1U);
    Xil_Out32(IIC_TX, IIC_STOP | (u32)n);
    return iic_rx(data, n);
}

/* 16-bit register address, then read n bytes (1..15) with a repeated start. */
int cam_iic_read16(u8 addr, u16 reg, u8 *data, int n)
{
    Xil_Out32(IIC_ISR, Xil_In32(IIC_ISR));
    Xil_Out32(IIC_TX, IIC_START | ((u32)addr << 1));
    Xil_Out32(IIC_TX, (u32)(reg >> 8));
    Xil_Out32(IIC_TX, (u32)(reg & 0xFF));
    Xil_Out32(IIC_TX, IIC_START | ((u32)addr << 1) | 1U);
    Xil_Out32(IIC_TX, IIC_STOP | (u32)n);
    return iic_rx(data, n);
}

/* 16-bit register address, then n data bytes. */
int cam_iic_write16(u8 addr, u16 reg, const u8 *data, int n)
{
    u8 buf[18];
    int i;

    if (n > 16) {
        return -1;
    }
    buf[0] = (u8)(reg >> 8);
    buf[1] = (u8)reg;
    for (i = 0; i < n; i++) {
        buf[2 + i] = data[i];
    }
    return cam_iic_write(addr, buf, n + 2);
}

/* 16-bit register address, then n data bytes of any length: the bytes are
 * fed to the 16-entry transmit FIFO as it empties (firmware download). */
#define SR_TXFULL   0x10U
int cam_iic_write16_long(u8 addr, u16 reg, const u8 *data, u32 n)
{
    u32 i, t;

    if (n == 0) {
        return -1;
    }
    Xil_Out32(IIC_ISR, Xil_In32(IIC_ISR));
    Xil_Out32(IIC_TX, IIC_START | ((u32)addr << 1));
    Xil_Out32(IIC_TX, (u32)(reg >> 8));
    Xil_Out32(IIC_TX, (u32)(reg & 0xFF));
    for (i = 0; i < n; i++) {
        for (t = 0; (Xil_In32(IIC_SR) & SR_TXFULL); t++) {
            if (t > 20000U || (Xil_In32(IIC_ISR) & (ISR_ARB | ISR_NACK))) {
                cam_iic_init();
                return -1;
            }
            usleep(1);
        }
        Xil_Out32(IIC_TX, data[i] | (i == n - 1U ? IIC_STOP : 0U));
    }
    return iic_wait_idle(ISR_ARB | ISR_NACK);
}

/* Select one switch channel (0..3), or none with ch < 0. */
int cam_mux_select(int ch)
{
    u8 v = (ch < 0) ? 0 : (u8)(1U << ch);

    return mux_addr ? cam_iic_write(mux_addr, &v, 1) : -1;
}

void cam_ctrl(u32 bits)
{
    Xil_Out32(CAM_GPIO_BASE + GPIO_DATA, bits);
}

/* Power the camera paths up: ISP out of reset and standby, IAS1 sensor out
 * of shutdown, RPi camera powered. */
void cam_power_up(void)
{
    cam_ctrl(0);
    usleep(10000);
    cam_ctrl(CAM_RPI_EN | CAM_IAS_XSHUT_B);
    usleep(20000);
    cam_ctrl(CAM_RPI_EN | CAM_IAS_XSHUT_B | CAM_AP1302_RST_B);
    usleep(50000);
}

static u16 id16(u8 addr, u16 reg)
{
    u8 b[2];

    if (cam_iic_read16(addr, reg, b, 2) != 0) {
        return 0xFFFF;
    }
    return (u16)((b[0] << 8) | b[1]);
}

void test_cam_iic(void)
{
    static const char *const ch_name[4] = { "ch0 ISP/J7", "ch1 IAS/J8", "ch2 RPi/J9", "ch3 unused" };
    u8 a, b, found[4] = { 0, 0, 0, 0 };
    int ch, ok = 1;
    u16 id;

    cam_iic_init();
    cam_power_up();

    /* The switch answers at 0x70..0x77; with no channel selected nothing
     * else is on the bus. */
    for (a = 0x70; a < 0x78 && !mux_addr; a++) {
        if (cam_iic_read(a, &b, 1) == 0) {
            mux_addr = a;
        }
    }
    if (!mux_addr) {
        xil_printf("  TCA9546 switch not found at 0x70..0x77\r\n");
        result("CAM I2C", 0);
        return;
    }
    xil_printf("  TCA9546 switch at 0x%02x\r\n", mux_addr);

    for (ch = 0; ch < 4; ch++) {
        if (cam_mux_select(ch) != 0) {
            ok = 0;
            continue;
        }
        xil_printf("  %s:", ch_name[ch]);
        for (a = 0x08; a < 0x78; a++) {
            if (a == mux_addr) {
                continue;
            }
            if (cam_iic_read(a, &b, 1) == 0) {
                xil_printf(" 0x%02x", a);
                found[ch]++;
            }
        }
        xil_printf("%s\r\n", found[ch] ? "" : " nothing");
    }

    /* Known chip IDs (16-bit register 0x0000 unless noted). */
    cam_mux_select(0);
    id = id16(0x3C, 0x0000);
    xil_printf("  AP1302 ISP (ch0, 0x3c): chip ID 0x%04x %s\r\n", id, id == 0x0265 ? "(AP1302)" : "(expected 0x0265)");
    ok = ok && id == 0x0265;

    /* The cameras on J9 and J8 are optional: report them, do not fail. */
    if (found[2]) {
        cam_mux_select(2);
        id = id16(0x10, 0x0000);
        xil_printf("  RPi camera (ch2, 0x10): model ID 0x%04x %s\r\n", id,
                   id == 0x0219 ? "(IMX219)" : id == 0x0477 ? "(IMX477)" : "(unknown; IMX219 = 0x0219)");
    } else {
        xil_printf("  J9: no Raspberry Pi camera answers (not connected?)\r\n");
    }
    if (!found[1]) {
        xil_printf("  J8: no IAS sensor answers (not connected?)\r\n");
    }

    cam_mux_select(1);
    if (found[1]) {
        for (a = 0x08; a < 0x78; a++) {
            if (a != mux_addr && cam_iic_read(a, &b, 1) == 0) {
                xil_printf("  IAS1 (ch1, 0x%02x): reg 0x3000 = 0x%04x, reg 0x0000 = 0x%04x\r\n",
                           a, id16(a, 0x3000), id16(a, 0x0000));
            }
        }
    }
    cam_mux_select(-1);
    result("CAM I2C", ok);
}
#endif
