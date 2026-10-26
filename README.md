# KV260 FPGA Base Project

Target board: AMD Kria KV260 Vision AI Starter Kit
SoM: K26 (Vivado part `xck26-sfvc784-2LV-c`, Zynq UltraScale+ MPSoC EV)
Tools: Vivado / Vitis 2026.1

A script-built Vivado project for the whole KV260 carrier, organised like
`ax7a200b-fpga-dev`: one top-level `src/rtl/top.v`, build options chosen with
`key=value` words, one constraint file per option, a single bare-metal test
program for the A53, a MicroBlaze V (RISC-V) co-processor in the fabric, and
simulation without Vivado.

The KV260 differs from a plain FPGA board in one way that shapes everything:
**the PL has no clock of its own.** Every fabric clock comes from the
processing system (PS), so the PS is part of every design and must be
initialised before the fabric runs. `tcl/program.tcl` does that over JTAG.

## Status

| Part | State |
|---|---|
| Default build (`pmod=1 fan=ps`) | Built and run on the board (2026-10-25): WNS 6.28 ns. BRAM, PMOD read-back and fan PWM PASS; fan steps 100/75/50/25 % |
| `fan=rtl` | Built and run (2026-10-26): with no program at all the fabric ramps the fan 100 → 75 → 50 → 25 % every 8 s (read back over JTAG); software takes over and hands back |
| `irq=1` | Run on the board (2026-10-26): PL timer interrupts reach the A53 through the GIC, 49-50 per 0.5 s |
| `dma=1` | Run on the board (2026-10-26): AXI CDMA copies 1 MB in DDR through S_AXI_HP1_FPD, 0 bytes wrong, ~1.5 GB/s, completion interrupt |
| `dp=1` | Run on the board (2026-10-26): DisplayPort link trains (2 lanes at 5.4 Gb/s), the PL pattern runs at 60 frames/s and streams at 1280x720. **The picture itself has not been checked by eye yet** |
| `iic=1` | Run on the board (2026-10-26): TCA9546 switch at 0x74; AP1302 ISP on channel 0 answers with chip ID 0x0265. Nothing answered on J8 (IAS) or J9 (RPi camera) |
| `cpu=mbv` | Run on the board (2026-10-26): the A53 loads the MicroBlaze V program, 1000 mailbox round trips in 9.5 ms with interrupts both ways, CRC-32 of 32 KB computed by the co-processor matches the A53's |
| `cam=rpi` | Written; being built. Needs an IMX219 camera that answers on J9 |
| `cam=isp`, `cam=ias` | Hardware scripted (lanes, rates, pins); sensor/ISP start-up code not written yet |
| PS peripherals in `board_test` | I2C1 bus scan (SoM EEPROM 0x50 and 13 other devices), Ethernet PHY (TI DP83867, MDIO address 1) PASS; SD card skipped (no card) |
| `tcl/program.tcl` | Works: restarts the PS in JTAG boot mode, recovers a wedged debug port with a JTAG power-on reset |
| Simulation | Verilator lint of 9 option sets, `fan_pwm` and `dp_tpg` testbenches pass |

`CLAUDE.md` describes how to run the tools in batch mode and what was learned
on the way.

## Getting started (Windows)

Build the hardware in the **Vivado Tcl Shell** (Start menu), from the repo root:

```tcl
cd C:/Users/<you>/CURRENT_WORK/duvitech/kria260-fpga-dev
set argv {}                   ;# default options; e.g. set argv {dp=1 cpu=mbv}
source tcl/create_project.tcl
source tcl/build.tcl          ;# 10-20 minutes; writes output/
```

Build the test program and run it (a **Vitis** command prompt, or any shell
after `call <Vitis>\settings64.bat`):

```bat
python sw\mbv\build.py        :: only needed after changing sw\mbv\ (RISC-V firmware)
cd sw
vitis -s create_vitis.py      :: platform + app -> C:\kv260_ws\board_test\build\board_test.elf
cd ..
xsdb tcl\program.tcl C:/kv260_ws/board_test/build/board_test.elf
```

After a change to `sw/board_test` only, `vitis -s create_vitis.py app`
rebuilds the program in about 30 s.

Open a terminal on the **second** FTDI port of the USB cable (COM10 on the
development PC), 115200 8N1, to see the results.

| Step | Last line printed |
|---|---|
| create_project | `INFO: Project kv260_base created in ... (cam=none cpu=none dma=0 dp=0 fan=ps iic=0 irq=0 pmod=1)` |
| build | `INFO: Build complete. WNS = ... ns, WHS = ... ns. Bitstream: output/kv260_base.bit` (both positive) |
| program | `INFO: Running ... on A53 #0 (console: ...)` |
| board_test | `==== 0 failure(s) ====` |

`xsdb tcl\program.tcl` without an ELF only loads the PL and initialises the
PS, which is enough for designs whose logic runs without software
(`fan=rtl`).

## Options

From a shell: `vivado -mode batch -source tcl/create_project.tcl -tclargs <options>`.
In the Tcl Shell: `set argv {<options>}` before `source tcl/create_project.tcl`.

| Option | Values | Default | Effect |
|---|---|---|---|
| `pmod` | `1`, `0` | `1` | PMOD J2 as 8 processor GPIO pins, direction per pin, pull-ups |
| `fan` | `ps`, `rtl` | `ps` | Fan PWM source. `ps`: PS timer TTC0 through EMIO, software sets the speed. `rtl`: `src/rtl/common/fan_pwm.v` ramps the fan by itself; software can take over |
| `irq` | `1`, `0` | `0` | PL timer interrupting the A53 (PL → PS interrupt) |
| `dma` | `1`, `0` | `0` | AXI CDMA in the fabric copying DDR to DDR through a PS high-performance port |
| `dp` | `1`, `0` | `0` | RTL 1280x720 test pattern into the PS DisplayPort controller's live-video input: J6 (DP) and J5 (HDMI) |
| `iic` | `1`, `0` | `0` | Camera I2C (through the carrier's TCA9546 switch) and the camera control pins |
| `cam` | `none`, `rpi`, `ias`, `isp` | `none` | MIPI CSI-2 camera capture into DDR: Raspberry Pi camera on J9, IAS module on J8, or the AP1302 ISP (J7). Turns `iic` on |
| `cpu` | `none`, `mbv` | `none` | MicroBlaze V co-processor with 128 KB of memory loaded by the A53, a mailbox and interrupts both ways |
| `jobs` | number | `8` | Parallel jobs (used by `build.tcl`) |

Re-running `create_project.tcl` recreates `vivado/`. Every option can be
combined with every other.

## Address map (A53 view, M_AXI_HPM0_LPD)

| Address | Block | Option |
|---|---|---|
| 0x8000_0000 | 8 KB scratch BRAM | always |
| 0x8001_0000 | `axi_gpio_pmod` | `pmod=1` |
| 0x8002_0000 | `axi_gpio_fan` (ch1 control, ch2 duty) | `fan=rtl` |
| 0x8003_0000 | `axi_timer_0` | `irq=1` |
| 0x8004_0000 | `axi_cdma_0` | `dma=1` |
| 0x8005_0000 | `axi_gpio_dp` (ch1 pattern control, ch2 frame count) | `dp=1` |
| 0x8006_0000 | `axi_iic_cam` | `iic=1` |
| 0x8007_0000 | `axi_gpio_cam` (ISP reset/standby, IAS shutdown, RPi enable) | `iic=1` |
| 0x8008_0000 | `mipi_csi2_rx_0` | `cam` |
| 0x8009_0000 | `v_frmbuf_wr_0` | `cam` |
| 0x800A_0000 | MicroBlaze V mailbox (A53 side) | `cpu=mbv` |
| 0x800B_0000 | `axi_gpio_mbv` (bit 0 = run) | `cpu=mbv` |
| 0x8010_0000 | MicroBlaze V memory, 128 KB (its address 0) | `cpu=mbv` |

PL → PS interrupts: `pl_ps_irq0[n]` is GIC interrupt 121 + n. Bit 0 timer,
1 CDMA, 2 camera I2C, 3 mailbox, 4 CSI-2 receiver, 5 frame buffer.

## What `board_test` checks

Each test prints PASS, FAIL or SKIP and is compiled in only when its hardware
is in the build:

| Test | What it does |
|---|---|
| BRAM | 8 KB written and read back |
| PMOD | All 8 pins driven and read back; pins wired together are listed (jumpers) |
| FAN | `fan=ps`: TTC0 PWM; `fan=rtl`: fabric duty read back, software override |
| PL IRQ | 100 timer interrupts per second through the GIC |
| CDMA | 1 MB DDR copy, compare, throughput |
| DP | Monitor found, link trained, 1280x720 stream; then red, green, blue, bars, ramp and a bouncing square, each printed |
| CAM I2C | Camera switch found, devices on each channel, ISP and sensor IDs |
| CAMERA | `cam=rpi`: IMX219 frames into DDR, colour-bar frames identical, live frames different |
| MBV | Program loaded, "ready" received, 1000 pings, CRC-32 offload |
| SD, I2C, ETH | PS peripherals: SD card block 0, I2C1 scan, Ethernet PHY |

Then it loops: a walking one on PMOD J2 and the fan stepping every 8 s.

## MicroBlaze V co-processor (`cpu=mbv`)

The co-processor is an AMD MicroBlaze V (RV32IMC) at 100 MHz with 128 KB of
local memory. The same block RAM appears to the A53 at 0x8010_0000, so the A53
writes the program and the data there:

1. `sw/mbv/` holds the firmware: start-up code, linker script, `main.c`.
   `python sw/mbv/build.py` compiles it with the RISC-V GCC that comes with
   Vitis and writes `sw/board_test/mbv_fw.h`.
2. `board_test` holds the co-processor in reset (`axi_gpio_mbv` bit 0 = 0),
   copies the program, and releases it.
3. They talk through the AMD mailbox: three-word commands from the A53, three-
   word replies, an interrupt on each side.

The co-processor can also be debugged over the same JTAG cable: xsdb lists it
as "RISC-V at USER2 / Hart #0".

## Programming and boot

`tcl/program.tcl` is an xsdb script. It writes the PS boot-mode override
(JTAG) and resets the PS, so the Kria boot firmware in the SoM's QSPI flash
does not start. The override lasts until the next power cycle. The flash is
never written; after power-off the board boots its normal firmware again.

`sw/boot.bif` describes a self-booting image (FSBL + bitstream + program) for
`bootgen`. Writing it to the SoM QSPI would replace the Kria boot firmware, so
use JTAG during development.

## Layout

```
tcl/common.tcl         board settings, options, helpers (latest_ip, force_connect)
tcl/create_project.tcl Vivado project from scratch
tcl/ps_config.tcl      PS configuration (DDR4, MIO, clocks, DisplayPort, AXI ports)
tcl/create_bd.tcl      block design "system": PS, SmartConnect, AXI slaves, interrupts
tcl/create_mbv.tcl     MicroBlaze V co-processor (cpu=mbv)
tcl/create_cam.tcl     MIPI CSI-2 camera capture (cam=...)
tcl/build.tcl          bitstream, XSA, psu_init.tcl, reports -> output/
tcl/program.tcl        xsdb: PS reset in JTAG mode, PL, psu_init, optional program
src/rtl/top.v          top level; sections per option
src/rtl/common/        fan_pwm.v, reset_sync.v
src/rtl/video/         dp_tpg.v (DisplayPort test pattern)
xdc/kv260_<feature>.xdc  one constraint file per option
sim/                   run_sim.sh (Verilator lint + Icarus testbenches), block-design stub
sw/board_test/         the A53 bare-metal test program
sw/mbv/                MicroBlaze V firmware and its build script
sw/create_vitis.py     Vitis platform + board_test application
docs/                  AMD data sheets, user guide, carrier schematics
```

## Simulation (no Vivado needed)

```bash
bash sim/run_sim.sh
```

Verilator (oss-cad-suite) lints `top.v` with every option set; Icarus Verilog
runs the self-checking testbenches. `sim/system_stub.v` stands in for the
block design.

## Board notes

- No PL oscillator, no PL LEDs, no PL push buttons. PL clocks come from the PS
  (`pl_clk0` = 100 MHz); the camera path makes 200/300 MHz with a clocking
  wizard, the DisplayPort pattern runs on the PS video clock (74.25 MHz).
- Bank 45 (3.3 V): PMOD, fan, camera control, camera I2C. Bank 66 (1.2 V):
  the three MIPI camera inputs.
- HDMI (J5) and DisplayPort (J6) are both driven by the PS DisplayPort
  controller (HDMI through a converter on the carrier); the PL reaches them
  through the controller's live-video input.
- Fan (A12) is active low: the fan runs at full speed whenever the PL is not
  driving it.
- Reference documents are in `docs/`: DS986 (KV260), DS987 (K26 SoM), UG1089
  (KV260 user guide), carrier schematics (`KV260_v1`, `KV260_v2`).
