# KV260 FPGA Base Project

Target board: AMD/Xilinx Kria KV260 Vision AI Starter Kit  
SoM: K26 (XCK26-SFVC784-2LV-C)  
Carrier: KV260 Carrier Card  

## Overview

This project establishes a minimal but functional PL base design for the KV260 that proves out the PS↔PL path. It uses:

- **SmartConnect** (Vivado 2025+, replaces deprecated AXI Interconnect)
- **AXI GPIO** driven from `M_AXI_HPM0_LPD` for 8 GPIO outputs on the PMOD connector J2
- **AXI BRAM Controller + BRAM** for a simple PS↔PL memory-mapped scratch space
- **Fan PWM**: PS TTC0 waveform out via EMIO → `fan_en_b` (A12), same as the official Kria platforms
- PL clock sourced from PS `pl_clk0` — no external PL oscillator pin on KV260

## Key Differences vs AXU2CGB

| Feature | AXU2CGB | KV260 |
|---------|---------|-------|
| Part | XCZU2CG-SFVC784-1-E | XCK26-SFVC784-2LV-C |
| DDR4 | 4 Gb, MIG config | 8 Gb, 16-bit x4 |
| PL Ref Clock | External 25 MHz on pin AB11 | PS pl_clk0 (no PL pin needed) |
| PL LEDs | 4× active-low, Bank 24 | None — no PL user LEDs on KV260 |
| PL Buttons | 4× active-low on PL | None — use PS GPIO MIO |
| Fan PWM | PL pin W12 | PL pin A12 (`fan_en_b`, active-low) via TTC0 EMIO |
| UART1 | MIO 24..25 | MIO 36..37 |
| USB3.0 GT Lane | GT Lane1 | GT Lane2 |
| DisplayPort | Lane0=GT Lane0 | Lane0=GT Lane1, Lane1=GT Lane0 |

---

## Create Project

In Windows open a TCL shell. In Linux, source the Vivado environment first:

```bash
source /tools/Xilinx/Vivado/2025.2/settings64.sh
```

Then create the Vivado project:

```bash
vivado -mode tcl -source tcl/create_project.tcl
```

## Build Bitstream

```bash
vivado -mode tcl -source tcl/build.tcl
```

---

# Bring-Up Notes (Vivado/Vitis 2025.2)

## 1. Hardware / Tooling

- Board: **Kria KV260 Vision AI Starter Kit**
- SoM: **K26** (XCK26-SFVC784-2LV-C, Zynq UltraScale+ EV)
- Tools: **Vivado 2026.1** / **Vitis 2026.1** (validated; scripts are not version-pinned)
- PL I/O used by this design:
  - `pmod[7:0]` – PMOD connector J2 (8 I/O, LVCMOS33)
  - `fan_en_b` – fan enable A12, active-low (HIGH = fan off), PWM from PS TTC0

---

## 2. Constraints (XDC)

XDC file: `xdc/kv260_base.xdc`

> **No PL user LEDs on KV260.** An earlier revision of this project constrained J10/K13/F11/A12 as "LEDs DS5–DS8" — those pins are actually (per the official kria-vitis-platforms / Kria-PYNQ designs): J10 = `ap1302_standby` (ISP), J11 = `ap1302_rst_b` (ISP), F11 = `cam_gpio`, A12 = `fan_en_b`. Driving them as LEDs toggles the ISP and the fan.

**Fan Enable (Bank 45, LVCMOS33):**

| Port | Carrier Net | SoM Connector | Package Pin | Polarity |
|------|-------------|---------------|-------------|----------|
| fan_en_b | HDA20 → Q20 gate | som240_1_c24 | A12 | HIGH = fan OFF, LOW/float = fan ON |

**PMOD J2 Package Pins (Bank 45, LVCMOS33):**

| Port | PMOD Pin (Digilent) | Schematic Pin (J2) | Carrier Net | Package Pin |
|------|--------------------|--------------------|-------------|-------------|
| pmod[0] | 1 (top row) | 1 | PMOD_HDA11 | H12 |
| pmod[1] | 2 | 3 | PMOD_HDA12 | E10 |
| pmod[2] | 3 | 5 | PMOD_HDA13 | D10 |
| pmod[3] | 4 | 7 | PMOD_HDA14 | C11 |
| pmod[4] | 7 (bottom row) | 2 | PMOD_HDA15 | B10 |
| pmod[5] | 8 | 4 | PMOD_HDA16_CC | E12 |
| pmod[6] | 9 | 6 | PMOD_HDA17 | D11 |
| pmod[7] | 10 | 8 | PMOD_HDA18 | B11 |

Two numbering schemes for the same connector: Digilent PMOD convention (top row 1–6, bottom row 7–12; GND = 5/11, 3V3 = 6/12) vs. the carrier schematic's zigzag header numbering (odd = top-row I/O, even = bottom-row I/O; GND = 9/10, 3V3 = 11/12). `pmod[5]` (HDA16_CC) is clock-capable. PMOD 3V3 is switched through a TPS22948 current-limited load switch (U42). Mapping verified against the official [Kria-PYNQ base.xdc](https://github.com/Xilinx/Kria-PYNQ/blob/main/kv260/base/vivado/constraints/base.xdc) and the carrier schematic.

> **Note:** The KV260 does NOT have dedicated PL push buttons. The carrier's push button connects to PS GPIO (MIO). If you need button-driven PL logic, read via AXI GPIO from the MIO side or use the PMOD / IAS expansion connectors. (The Raspberry Pi 40-pin header exists on the KR260, not the KV260.)

If you see:
```text
[Common 17-55] 'set_property' expects at least one object.
```
a constraint is referencing a port not declared in `top.v`. Comment out or remove those lines.

---

## 3. Block Design Overview (`zynq_bd`)

| IP Instance | Type | Description |
|---|---|---|
| `zynq_ultra_ps_e_0` | PS | Zynq MPSoC PS (K26 SoM) |
| `rst_pl_clk0` | proc_sys_reset | Synchronized reset from pl_resetn0 |
| `axi_sc_0` | SmartConnect | 1 master → 2 slaves |
| `axi_bram_ctrl_0` | AXI BRAM Controller | PS↔PL scratch memory |
| `bram_0` | Block Memory Generator | 8KB RAM |
| `axi_gpio_0` | AXI GPIO | 8-bit output → PMOD J2 |
| `fan_slice` | xlslice | TTC0 EMIO wave_out[0] → `fan_en_b` |

### 3.1 AXI Connections

```
ps/M_AXI_HPM0_LPD  →  axi_sc_0/S00_AXI
axi_sc_0/M00_AXI   →  axi_bram_ctrl_0/S_AXI
axi_sc_0/M01_AXI   →  axi_gpio_0/S_AXI
axi_bram_ctrl_0/BRAM_PORTA  ↔  bram_0/BRAM_PORTA
ps/emio_ttc0_wave_o[0]  →  fan_slice  →  fan_en_b (A12)
```

### 3.2 Address Map (fixed in `create_bd.tcl`)

| Slave | Base Address | Range | Function |
|-------|-------------|-------|----------|
| `axi_bram_ctrl_0` | `0x8000_0000` | 8K | Scratch BRAM |
| `axi_gpio_0` | `0x8001_0000` | 64K | PMOD J2 |

Addresses are assigned explicitly with `assign_bd_address -offset`, so bare-metal code can hardcode them (see `sw/src/main.c`). The fan is not AXI-mapped — it is TTC0 channel 0 in the PS (`0xFF11_0000`), driven with the `xttcps` driver.

### 3.3 GPIO Register Interface

The AXI GPIO core is **pure output** (`C_ALL_OUTPUTS=1`). Channel-1 registers (PG144):

| Offset | Register | Notes |
|--------|----------|-------|
| `0x0000` | GPIO_DATA | Write output value |
| `0x0004` | GPIO_TRI | 0 = output (no-op when C_ALL_OUTPUTS=1) |

Example (bare-metal, A53):
```c
Xil_Out32(0x80010000 + 0x4, 0x00); // PMOD: direction = output
Xil_Out32(0x80010000 + 0x0, 0x55); // Drive PMOD pins 1,3,7,9 high
```

### 3.4 Fan PWM (TTC0 → EMIO → A12)

The carrier fan circuit (UG1089 / carrier schematic): HDA20 drives Q20, which
gates Q18, the fan's low-side switch. **Polarity is inverted** — `fan_en_b`
HIGH turns the fan OFF; LOW or floating runs it (failsafe while the PL is
unconfigured or the TTC idle).

Software PWM via `xttcps` (see [main.c](sw/src/main.c)):
- TTC0 ch0, interval mode + match mode + waveform out, `WAVE_POLARITY` set
  → output HIGH from interval start until match, LOW to rollover
- fan power % = LOW fraction → `match = period * (100 - percent) / 100`
- ~100 Hz PWM. Keep it slow: Q18's gate is fed through a 10k pull-up
  (≈5 µs edges), so 25 kHz-class PWM would be badly distorted.
- Plain on/off "GPIO" behavior = 0% / 100% duty.

---

## 4. Top-Level RTL (`top.v`)

The top module connects the PMOD GPIO and fan enable to the block design outputs.

```
top.v
 └─ zynq_bd_wrapper (generated by Vivado)
     ├─ axi_gpio_0/gpio_io_o     → pmod_gpio_o[7:0] → pmod[7:0]
     └─ ps/emio_ttc0_wave_o[0]   → fan_en_b         → A12 (fan)
```

No push-button port — the KV260 push button connects to PS GPIO MIO.

---

## 4b. Bare-Metal Software (`sw/`)

| File | Purpose |
|------|---------|
| `sw/src/main.c` | Standalone A53 app: walking-one on PMOD, fan PWM ramp via TTC0 |
| `sw/create_vitis.py` | Creates the Vitis 2025.2 platform + app components |
| `sw/run_jtag.tcl` | xsdb script: configure PL, psu_init, download & run ELF |
| `sw/boot.bif` | bootgen image description (FSBL + bitstream + app) |

### Build flow

```bash
# 1. Hardware: bitstream + XSA
vivado -mode tcl -source tcl/create_project.tcl
vivado -mode tcl -source tcl/build.tcl        # writes vivado/kv260_base.xsa

# 2. Software: platform + app (from sw/)
cd sw
vitis -s create_vitis.py                      # builds C:\kv260_ws\pmod_gpio\build\pmod_gpio.elf

# 3. Run over JTAG (board powered, USB J4 connected)
xsdb run_jtag.tcl
```

> **Windows workspace location:** the Vitis workspace defaults to `C:\kv260_ws` (override with the `VITIS_WORKSPACE` env var). It cannot live inside this repo on Windows — the standalone BSP build creates ~180-char-deep paths and hits the 260-char MAX_PATH limit under a long repo path.

`run_jtag.tcl` does the full bare-metal bring-up: halts the PSU, loads the bitstream into the PL (`fpga`), runs `psu_init` (clocks/DDR/MIO from this design), removes PS↔PL isolation, then downloads and starts the ELF on A53 core 0. UART console is the second FTDI COM port at 115200 8N1.

Expected behavior: a single high pin walks across PMOD J2 pins 1→2→3→4→7→8→9→10 (3.3V logic) at 4 steps/second, while the fan steps 100% → 75% → 50% → 25% → 100% every 8 seconds (audible) with each change printed on the UART.

> **Booting without JTAG:** `bootgen -arch zynqmp -image boot.bif -o BOOT.BIN -w on` produces a self-booting image (FSBL + bitstream + app). Note the KV260 boots from SOM QSPI — flashing a custom BOOT.BIN replaces the Kria boot firmware, so prefer JTAG during development.

---

## 5. PS Configuration Notes (K26 SoM)

The K26 SoM has fixed MIO assignments. Key peripherals enabled in `create_bd.tcl`:

| Peripheral | MIO / GT Lane |
|---|---|
| QSPI (boot flash) | MIO 0..5 |
| I2C1 | MIO 24..25 |
| UART1 (console) | MIO 36..37 |
| SD1 (MicroSD) | MIO 39..51, CD=MIO 45 |
| USB0 | MIO 52..63 |
| USB3.0 | GT Lane2 |
| GEM3 (Ethernet) | MIO 64..75, MDIO=MIO 76..77 |
| DisplayPort | Lane0=GT Lane1, Lane1=GT Lane0 |
| PL Clock 0 | 100 MHz (IOPLL) |
| DDR4 | 8 Gb, 1200 MHz |

> The K26 SoM eMMC (SD0) is excluded here — it is managed by the SoM boot flow separately.

---

## 6. TCL Reference

### Query PS cell properties
```tcl
# List all PS config properties matching a keyword
set props [report_property [get_bd_cells zynq_ultra_ps_e_0] -all]
foreach line [split $props "\n"] {
    if {[string match -nocase "*SD*" $line]} { puts $line }
}
```

### Find available board parts
```tcl
get_board_parts *kv260*
```

---

## 7. Docs

Reference documentation in `docs/`:
- `ds986-kv260-starter-kit.pdf` — KV260 Data Sheet
- `ug1089-kv260-starter-kit.pdf` — KV260 Starter Kit User Guide (schematics, pin table)
