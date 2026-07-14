###############################################################################
# KV260 Vision AI Starter Kit – PL I/O Constraints
# Device:  XCK26-SFVC784-2LV-C  (K26 SoM)
# Carrier: KV260 Carrier Card
#
# Pin mapping source:
#   XilinxBoardStore/boards/Xilinx/kv260_som/1.4/part0_pins.xml
#   XilinxBoardStore/boards/Xilinx/kv260_carrier/1.3/board.xml
#   UG1089 – Kria KV260 Starter Kit User Guide
###############################################################################

###############################################################################
# NO PL USER LEDS ON KV260
#
# The KV260 carrier has no PL-connected user LEDs. Pins previously (and
# wrongly) constrained here as LEDs actually are, per the official
# kria-vitis-platforms / Kria-PYNQ designs:
#   J10 → ap1302_standby (ISP)     J11 → ap1302_rst_b (ISP)
#   F11 → cam_gpio                 A12 → fan_en_b (fan enable, active-low)
###############################################################################

###############################################################################
# Fan Enable (Bank 45, LVCMOS33) – carrier J13 fan header
#
# HDA20 → som240_1_c24 → A12. Drives Q20 gate on the carrier:
#   pin HIGH        → fan OFF
#   pin LOW / float → fan ON  (failsafe: fan runs when PL unconfigured)
#
# Driven by PS TTC0 wave_out[0] via EMIO for software PWM (~100 Hz -
# keep it slow, the carrier's 10k gate pull-up gives ~5 us edges).
###############################################################################
set_property PACKAGE_PIN A12     [get_ports fan_en_b]
set_property IOSTANDARD LVCMOS33 [get_ports fan_en_b]
set_property DRIVE 4             [get_ports fan_en_b]
set_property SLEW SLOW           [get_ports fan_en_b]

###############################################################################
# Push Buttons
#
# The KV260 carrier card does NOT have dedicated PL-accessible push buttons.
# The single user push button (SW1) connects to PS GPIO MIO.
# Use PS GPIO MIO from software if button input is required, or route
# a button signal through the Raspberry Pi 40-pin or IAS expansion connectors.
###############################################################################

###############################################################################
# PL Reference Clock
#
# The KV260 has no standalone PL crystal oscillator driving an I/O bank pin.
# The PL fabric clock (pl_clk0, default 100 MHz) is generated internally by
# the PS CRL_APB PLL and does not require an XDC pin constraint.
###############################################################################

###############################################################################
# PMOD Connector J2 (Bank 45, LVCMOS33)
#
# NOTE on pin numbering — two schemes exist for the same connector:
#  * Digilent PMOD convention: top row 1-6 (4 I/O + GND + 3V3),
#    bottom row 7-12 (4 I/O + GND + 3V3)
#  * Carrier schematic (HDR_2X6_F_RA) zigzag numbering: odd pins
#    1,3,5,7 = top-row I/O; even pins 2,4,6,8 = bottom-row I/O;
#    9/10 = GND; 11/12 = PMOD_3V3
#
# Port index → Digilent pin / schematic pin → net → K26 package pin
# (verified against Xilinx/Kria-PYNQ base.xdc AND carrier schematic):
#   pmod[0] : PMOD 1  / J2.1 → PMOD_HDA11    → H12
#   pmod[1] : PMOD 2  / J2.3 → PMOD_HDA12    → E10
#   pmod[2] : PMOD 3  / J2.5 → PMOD_HDA13    → D10
#   pmod[3] : PMOD 4  / J2.7 → PMOD_HDA14    → C11
#   pmod[4] : PMOD 7  / J2.2 → PMOD_HDA15    → B10
#   pmod[5] : PMOD 8  / J2.4 → PMOD_HDA16_CC → E12  (clock-capable)
#   pmod[6] : PMOD 9  / J2.6 → PMOD_HDA17    → D11
#   pmod[7] : PMOD 10 / J2.8 → PMOD_HDA18    → B11
#
# PMOD 3V3 is switched/current-limited by U42 (TPS22948), not raw PL_3V3.
###############################################################################
set_property PACKAGE_PIN H12 [get_ports {pmod[0]}]  ;# HDA11 / J2.1
set_property PACKAGE_PIN E10 [get_ports {pmod[1]}]  ;# HDA12 / J2.3
set_property PACKAGE_PIN D10 [get_ports {pmod[2]}]  ;# HDA13 / J2.5
set_property PACKAGE_PIN C11 [get_ports {pmod[3]}]  ;# HDA14 / J2.7
set_property PACKAGE_PIN B10 [get_ports {pmod[4]}]  ;# HDA15 / J2.2
set_property PACKAGE_PIN E12 [get_ports {pmod[5]}]  ;# HDA16_CC / J2.4
set_property PACKAGE_PIN D11 [get_ports {pmod[6]}]  ;# HDA17 / J2.6
set_property PACKAGE_PIN B11 [get_ports {pmod[7]}]  ;# HDA18 / J2.8

set_property IOSTANDARD LVCMOS33 [get_ports {pmod[*]}]
set_property DRIVE 4             [get_ports {pmod[*]}]
set_property SLEW SLOW           [get_ports {pmod[*]}]

###############################################################################
# IAS Camera Connector (J3/J4) – HP banks, MIPI DPHY
# MIPI CSI-2 data lanes are constrained via the MIPI DPHY IP, not here.
# Control signals (I2C, GPIO, power) are on PS MIO or HP bank I/O.
###############################################################################

###############################################################################
# End of KV260 Constraints
###############################################################################
