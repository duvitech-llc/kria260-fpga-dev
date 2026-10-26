# KV260 FPGA base project: notes for Claude

Vivado project for the AMD Kria KV260 (K26 SoM, `xck26-sfvc784-2LV-c`), built
entirely from Tcl scripts, organised like `../ax7a200b-fpga-dev`. `README.md`
has the user-facing description; read it first.

## Current state (update this section as things are verified)

Plan (approved 2026-10-25):
`C:\Users\gvigelet\.claude\plans\pasted-content-id-aec5-review-the-shimmering-starfish.md`.
User decisions: MicroBlaze V as the RISC-V core, bare metal only (no Linux).
User has: IAS AR1335 module on J7 (via the AP1302 ISP), an IAS module on J8,
an RPi camera on J9, a DP/HDMI monitor, PMOD devices.

Verified on the board with Vivado/Vitis 2026.1 (`C:\AMDDesignTools\2026.1`):

- 2026-10-25, default (`pmod=1 fan=ps`): WNS 6.28 ns; BRAM, PMOD read-back,
  fan PWM PASS; console shows the fan stepping.
- 2026-10-26, `fan=rtl`: WNS 6.13 ns. With only `program.tcl` (no ELF) the
  fabric PWM ramps 100/75/50/25 % every ~8 s (polled `0x8002_0008` with
  `mrd -force`); `board_test` takes over and hands back.
- 2026-10-26, `irq=1 dma=1 dp=1`: timer 49-50 interrupts / 0.5 s; CDMA 1 MB
  in 657 us, 0 wrong; DP link trains 2 x 5.4 Gb/s, pattern 30 frames / 0.5 s
  before and after streaming. **Picture not yet confirmed by the user.**
- 2026-10-26, `irq=1 dma=1 dp=1 iic=1 cpu=mbv`: WNS 3.98 ns, no critical
  warnings in implementation, every register clocked. `board_test`
  0 failures: TCA9546 at 0x74, AP1302 ID 0x0265 on channel 0; **nothing
  answers on channel 1 (J8) or 2 (J9)**, even with `rpi_cam_en` and
  `ias_xshutdown_b` high. Either those cameras are not connected or need
  something else; ask the user before blaming the design. MBV: 1000 pings
  in 9.5 ms, CRC-32 of 32 KB matches (25 ms on the co-processor).
- 2026-10-26, `irq=1 dma=1 dp=1 cam=rpi cpu=mbv`: WNS 0.54 ns, no critical
  warnings; MBV passes with the mailbox on the PS-domain reset. CAMERA
  skipped (no IMX219 on J9).
- 2026-10-26, `dp=1 cam=isp cpu=mbv`: WNS 0.49 ns. **ISP camera works**:
  AP1302 firmware loads (attempt 1 often ends with a wrong CRC, attempt 2
  passes; the Linux driver retries the same way), CSI-2 receiver sees
  1085 lines x 3840 bytes, data type 0x1E (YUV422 8-bit), 30 frames/s into
  DDR, YUYV byte order (Y in even bytes). A frame copied with xsdb showed a
  dark room. `board_test` 0 failures.
- PS: I2C1 devices 0x2C 0x2D 0x30 0x31 0x32 0x33 0x40 0x50 0x51 0x58 0x59 0x68
  0x70 0x73; Ethernet PHY TI DP83867 (0x2000 0xA231) at MDIO 1; no SD card in
  the slot (SD test SKIPs).
- PS console = PS UART1 = **COM10** (FTDI channel B) on the user's PC.

Lessons from the board (all fixed in the scripts/code):

- `program.tcl`: after the Kria boot firmware has run, `stop` leaves the A53
  cores unusable ("Memory write error at 0x0. Cortex-A53 #0: EDITR not
  ready"). The script writes the JTAG boot-mode override
  (`mwr 0xff5e0200 0x0100`) and does `rst -system` first.
- A PL access that never completes wedges the debug port ("AXI AP
  transaction error, DAP status 0x30000021") and the PSU target disappears.
  `rst -por` on the PS TAP recovers without a power cycle; `program.tcl` does
  it automatically.
- The mailbox shared the co-processor's reset at first: while the
  co-processor was held in reset the A53's mailbox access never completed and
  blocked the whole PS SmartConnect. Its S1 reset is now the PS-domain reset
  (`create_mbv.tcl`); not yet rebuilt and re-run with that change at the time
  of writing. `board_test` also only touches the mailbox after releasing the
  co-processor.
- MicroBlaze V takes its interrupt handler address from the AXI INTC (IVAR),
  not from `mtvec` (as in the Artix repo); the firmware sets `IVAR0`.
- MicroBlaze V here is built with `C_INTERRUPT_WAKEUP = 0`: `wfi` is never
  woken by an interrupt. The firmware spins instead of `wfi`.
- The PS IP declares no clock for its DisplayPort video clock; `kv260_dp.xdc`
  creates `vid_clk` on `PS8_i/DPVIDEOREFCLK` (implementation only: in
  synthesis the PS is out of context and the pin does not exist).
- `XAVBuf_SetPixelClock()` assumes another PLL reference (it printed a
  3.33 GHz input) and is not used; `psu_init` sets VPLL to 74.25 MHz.
- In the SDT BSP the timer API is `xiltimer.h` (not `xtime_l.h`).
- Mailbox interrupt handlers (both sides) must clear the interrupt status
  *before* emptying the FIFO; the other order lost a word as soon as the
  camera interrupts slowed the A53 down.
- `XVFrmbufWr_SetCallback` asserts a non-NULL reference, and a failed
  assertion hangs the program silently (find it with xsdb `stop`, `bt`).
  In interrupt mode the driver clears auto-restart: the done callback must
  call `XVFrmbufWr_Start` again.
- The camera clocking wizard must not be given an input frequency:
  `pl_clk0` is really 99.999001 MHz and any typed value fails validation.
- The subset converter's input widths must be set from the receiver's
  `video_out` before its remap strings (`create_cam.tcl`).
- `XPAR_MIPI_CSI2_RX_0_RX_CSI_LANES` is the lane-count macro in the SDT BSP.
- Debugging a hang: `xsdb` -> `targets -set -filter {name =~ "*A53*#0"}`,
  `stop`, `bt` gives the call stack with source lines.
- `vitis -s create_vitis.py` leaves a `vitis-server` java.exe running, which
  locks `C:\kv260_ws` for the next run. Stop it after each run (check the
  start time; do not kill a server the user's Vitis IDE owns).

## Running the tools

```
cmd /c "call C:\AMDDesignTools\2026.1\Vivado\settings64.bat && vivado -mode batch -nojournal -log vivado_logs\create.log -source tcl\create_project.tcl -tclargs dp=1 cpu=mbv"
cmd /c "call C:\AMDDesignTools\2026.1\Vivado\settings64.bat && vivado -mode batch -nojournal -log vivado_logs\build.log -source tcl\build.tcl"
python sw\mbv\build.py
cmd /c "call C:\AMDDesignTools\2026.1\Vitis\settings64.bat && cd sw && vitis -s create_vitis.py"       (or "... create_vitis.py app" after source-only changes, ~30 s)
cmd /c "call C:\AMDDesignTools\2026.1\Vitis\settings64.bat && xsdb tcl\program.tcl C:/kv260_ws/board_test/build/board_test.elf"
```

- `vivado.bat` and `xsdb.bat` split arguments at `=`: `fan=rtl` arrives as
  `fan rtl`. `parse_options` and `program.tcl` accept both forms.
- Run from the repo root with `-log` into `vivado_logs/`; search for `ERROR:`
  and `CRITICAL WARNING:` (also in `vivado/kv260_base.runs/impl_1/runme.log`)
  and check `output/timing_summary.rpt` for `no_clock (0)`. Builds take 10-20
  minutes; run them in the background.
- Console capture: pyserial is installed; open COM10 at 115200 before
  starting the program (the full `board_test` run takes about a minute).
- xsdb reads of PL addresses need `mrd -force` (they are not in its memory map).
- Simulation: `bash sim/run_sim.sh`. Verilator only lints here (no C++
  compiler); Icarus runs the testbenches.
- File edits on this machine: native Python writes CRLF in text mode and the
  Bash tool joins backslash-newline pairs. Use the Write/Edit tools for source,
  or `open(..., newline='')`. `.gitattributes` keeps the repo LF.

## Structure and options

`tcl/common.tcl` parses `pmod`, `fan`, `irq`, `dma`, `dp`, `iic`, `cam`, `cpu`,
`jobs` (see README). They become the defines `USE_PMOD`, `USE_FAN_RTL`,
`USE_DP`, `USE_IIC`, `USE_CAM` (+ `CAM_LANES`), `USE_MBV` for `src/rtl/top.v`.
The block design (`tcl/create_bd.tcl`, PS settings in `tcl/ps_config.tcl`) is
always present, because the PS supplies the PL clock; it exports
`pl_clk`/`pl_rst` for RTL in `top.v`. `create_mbv.tcl` and `create_cam.tcl`
are sourced from `create_bd.tcl` before the PS SmartConnect is built and add
to its `slaves` and `irqs` lists.

The fixed address map and interrupt bits are in the README; keep them, since
`sw/board_test` falls back to them.

## Conventions

- Verilog-2001 for synthesizable RTL (`.v`), SystemVerilog for testbenches.
  Files start with `` `default_nettype none `` and end with
  `` `default_nettype wire ``. Synchronous active-high resets inside the design.
- Do not hard-code IP versions; use `latest_ip` from `tcl/common.tcl`.
- New pins go in a constraint file loaded only when its ports exist
  (`xdc/kv260_<feature>.xdc`, added in `create_project.tcl`).
- New AXI slaves: append `{cell/interface offset range}` to `slaves` in
  `create_bd.tcl` (before the SmartConnect is created); interrupts to `irqs`.
- `sim/system_stub.v` is simulation-only; keep its ports in step with the
  block design.
- Generated, never commit: `vivado/`, `output/`, `vivado_logs/`, `.Xil/`,
  `sw/mbv/build/`. `sw/board_test/mbv_fw.h` is generated but committed (the
  A53 program needs it to build).
- Never write the SoM QSPI flash (it holds the Kria boot firmware).
- `docs/` is vendor reference material; do not edit.

## Board facts

Sources: Vivado 2026.1 board store `kv260_som/2.0/part0_pins.xml`,
`kv260_carrier/2.0/board.xml` + `preset.xml` (the board files are not
installed, so the PS is configured by hand); AMD
`kria-vitis-platforms/kv260/platforms/kv260_bist/xdc/pin.xdc`; UG1089; AMD's
Linux `ap1302.c` and `imx219.c`.

- No PL oscillator; no PL LEDs/buttons. HDMI J5 and DP J6 both come from the
  PS DisplayPort controller (GT lanes 0/1, AUX on MIO 27..30, reference clock
  27 MHz on Ref Clk0); the PL GTH quad is unused.
- PMOD J2: H12 E10 D10 C11 B10 E12 D11 B11 (bank 45, LVCMOS33).
- Fan `fan_en_b` A12, active low.
- Camera control: `ap1302_rst_b` J11, `ap1302_standby` J10,
  `ias_xshutdown_b` K13, `rpi_cam_en` F11.
- Camera I2C SCL G11 / SDA F10 -> TCA9546 at 0x74: ch0 AP1302 (0x3C) + AR1335
  (J7), ch1 IAS sensor (J8), ch2 RPi camera (J9, IMX219 at 0x10).
- MIPI (bank 66): ISP J7 4-lane clk G1/F1, data E1/D1 F2/E2 G3/F3 E4/E3
  (1200 Mb/s); IAS J8 4-lane clk C1/B1, data A2/A1 B3/A3 B4/A4 D4/C4
  (880 Mb/s RAW10); RPi J9 2-lane clk D7/D6, data E5/D5 G6/F6 (912 Mb/s RAW10).
- AP1302 firmware (`ap1302_ar1335_single_fw.bin`): 4-byte header
  {u16 pll_init_size, u16 crc}, written through the 8 KB window at register
  0x8000; BOOTDATA_STAGE (0x6002) = 2 after the PLL part, 0xFFFF at the end;
  CRC in 0xF052. Source: Ubuntu package `linux-firmware-xilinx-ap1302` 2.0.
  AMD-licensed: never commit it.
- PS: DDR4 8 Gb x16 64-bit 2400 (CWL must be 16 in 2026.1), UART1 MIO 36..37,
  I2C1 MIO 24..25, SD1 MIO 39..51, USB0 MIO 52..63 + GT lane 2, GEM3 MIO 64..77,
  DP lanes "Dual Lower" (GT lane 1, 0).
