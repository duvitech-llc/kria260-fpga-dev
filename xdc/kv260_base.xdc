###############################################################################
# KV260 base constraints, always loaded.
# Device: XCK26-SFVC784-2LV-C (K26 SoM), carrier: KV260 (rev 1.0 and 2.0)
#
# Pin sources: XilinxBoardStore kv260_som/2.0 part0_pins.xml and
# kv260_carrier/2.0 board.xml (both shipped with Vivado 2026.1), AMD
# kria-vitis-platforms kv260_bist pin.xdc, UG1089, carrier schematics in docs/.
#
# The KV260 has no PL oscillator (pl_clk0 comes from the PS), no PL LEDs and
# no PL push buttons. Bank 45 (HD, 3.3 V) holds the PMOD, fan, camera control
# and camera I2C pins; bank 66 (HP, 1.2 V) holds the three MIPI inputs.
###############################################################################

# Fan enable, carrier J13 fan header: HDA20 -> som240_1_c24 -> A12, gate of Q20.
#   high = fan OFF, low or floating = fan ON (fan runs while the PL is blank).
# Driven by PS TTC0 waveform 0 through EMIO; keep the PWM slow (~100 Hz): the
# carrier's 10k gate pull-up gives ~5 us edges.
set_property PACKAGE_PIN A12     [get_ports fan_en_b]
set_property IOSTANDARD LVCMOS33 [get_ports fan_en_b]
set_property DRIVE 4             [get_ports fan_en_b]
set_property SLEW SLOW           [get_ports fan_en_b]

# Shut the device down if the die overheats (as AMD's Kria platforms do).
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN ENABLE [current_design]
