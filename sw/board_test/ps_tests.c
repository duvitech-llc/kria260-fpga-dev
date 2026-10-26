/*
 * KV260 board test: PS peripherals reached through the MIO, no PL involved.
 * All three are read-only: nothing on the SD card, the I2C devices or the
 * Ethernet PHY is changed.
 */
#include "board_test.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "sleep.h"
#include "xsdps.h"
#include "xiicps.h"
#include "xemacps.h"

/* ---- SD card (SD1, microSD slot J11) ---------------------------------------
 * Initialises the card and reads block 0 (MBR: ends in 0x55 0xAA). */
void test_ps_sd(void)
{
    static XSdPs sd;
    static u8 blk[512] __attribute__((aligned(64)));
    XSdPs_Config *cfg = XSdPs_LookupConfig(XPAR_XSDPS_0_BASEADDR);

    if (cfg == NULL || XSdPs_CfgInitialize(&sd, cfg, cfg->BaseAddress) != XST_SUCCESS) {
        result("SD", 0);
        return;
    }
    if (XSdPs_CardInitialize(&sd) != XST_SUCCESS) {
        skipped("SD", "no card, or the card did not initialise");
        return;
    }
    Xil_DCacheInvalidateRange((UINTPTR)blk, sizeof(blk));
    if (XSdPs_ReadPolled(&sd, 0, 1, blk) != XST_SUCCESS) {
        xil_printf("  block 0 read failed\r\n");
        result("SD", 0);
        return;
    }
    Xil_DCacheInvalidateRange((UINTPTR)blk, sizeof(blk));
    xil_printf("  card initialised (%s), block 0 ends in 0x%02x 0x%02x\r\n",
               sd.HCS ? "SDHC/SDXC" : "SDSC", blk[510], blk[511]);
    result("SD", blk[510] == 0x55 && blk[511] == 0xAA);
}

/* ---- I2C1 (MIO 24..25): SoM and carrier management bus ----------------------
 * Probes every 7-bit address with a one-byte read. The SoM EEPROM (24AA025
 * type, 0x50) must answer. */
void test_ps_i2c(void)
{
    static XIicPs iic;
    XIicPs_Config *cfg = XIicPs_LookupConfig(XPAR_XIICPS_0_BASEADDR);
    u8 b;
    u32 a, found = 0, eeprom = 0, t;

    if (cfg == NULL || XIicPs_CfgInitialize(&iic, cfg, cfg->BaseAddress) != XST_SUCCESS) {
        result("I2C", 0);
        return;
    }
    XIicPs_SetSClk(&iic, 100000);
    xil_printf("  I2C1 devices:");
    for (a = 0x08; a < 0x78; a++) {
        if (XIicPs_MasterRecvPolled(&iic, &b, 1, (u16)a) == XST_SUCCESS) {
            xil_printf(" 0x%02lx", a);
            found++;
            if (a == 0x50) {
                eeprom = 1;
            }
        }
        for (t = 0; t < 1000U && XIicPs_BusIsBusy(&iic); t++) {
            usleep(10);
        }
    }
    xil_printf("%s\r\n", found ? "" : " none");
    result("I2C", eeprom);
}

/* ---- Ethernet (GEM3, MIO 64..77, RJ45 J10) ----------------------------------
 * Finds the PHY on the management bus and reports its ID and link state. */
void test_ps_eth_phy(void)
{
    static XEmacPs emac;
    XEmacPs_Config *cfg = XEmacPs_LookupConfig(XPAR_XEMACPS_0_BASEADDR);
    u16 id1 = 0, id2 = 0, bmsr = 0;
    u32 a, phy = 32;

    if (cfg == NULL || XEmacPs_CfgInitialize(&emac, cfg, cfg->BaseAddress) != XST_SUCCESS) {
        result("ETH", 0);
        return;
    }
    XEmacPs_SetMdioDivisor(&emac, MDC_DIV_224);
    for (a = 0; a < 32; a++) {
        XEmacPs_PhyRead(&emac, a, 2, &id1);
        XEmacPs_PhyRead(&emac, a, 3, &id2);
        if (id1 != 0xFFFF && id1 != 0x0000) {
            phy = a;
            break;
        }
    }
    if (phy == 32) {
        xil_printf("  no PHY answers on MDIO\r\n");
        result("ETH", 0);
        return;
    }
    XEmacPs_PhyRead(&emac, phy, 1, &bmsr);          /* link bit is latched low: read twice */
    XEmacPs_PhyRead(&emac, phy, 1, &bmsr);
    xil_printf("  PHY at MDIO address %lu, ID 0x%04x 0x%04x, link %s\r\n",
               phy, id1, id2, (bmsr & 0x0004) ? "up" : "down (no cable?)");
    result("ETH", 1);
}
