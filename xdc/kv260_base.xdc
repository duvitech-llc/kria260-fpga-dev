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
# User LEDs (Bank 45, LVCMOS33, Active-HIGH)
#
# Carrier net → SoM connector → K26 package pin mapping:
#   DS5 (LED0) : leds_4bits_tri_o[1] → som240_1_b17 → J10
#   DS6 (LED1) : leds_4bits_tri_o[2] → som240_1_b18 → K13
#   DS7 (LED2) : leds_4bits_tri_o[3] → som240_1_a15 → F11
#   DS8 (LED3) : leds_4bits_tri_o[4] → som240_1_c24 → A12
#
# Drive HIGH  to turn LED ON
# Drive LOW   to turn LED OFF
###############################################################################
set_property PACKAGE_PIN J10 [get_ports {leds[0]}]  ;# LED0 / DS5
set_property PACKAGE_PIN K13 [get_ports {leds[1]}]  ;# LED1 / DS6
set_property PACKAGE_PIN F11 [get_ports {leds[2]}]  ;# LED2 / DS7
set_property PACKAGE_PIN A12 [get_ports {leds[3]}]  ;# LED3 / DS8

set_property IOSTANDARD LVCMOS33 [get_ports {leds[*]}]
set_property DRIVE 4             [get_ports {leds[*]}]
set_property SLEW SLOW           [get_ports {leds[*]}]

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
# 12-pin PMOD: pins 1-4 = top-row I/O, 7-10 = bottom-row I/O,
# pins 5/11 = GND, pins 6/12 = 3V3.
#
# Port index → PMOD physical pin → HDA net → K26 package pin
# (mapping verified against Xilinx/Kria-PYNQ kv260 base.xdc):
#   pmod[0] : pin 1  → HDA11 → H12
#   pmod[1] : pin 2  → HDA12 → E10
#   pmod[2] : pin 3  → HDA13 → D10
#   pmod[3] : pin 4  → HDA14 → C11
#   pmod[4] : pin 7  → HDA15 → B10
#   pmod[5] : pin 8  → HDA16 → E12
#   pmod[6] : pin 9  → HDA17 → D11
#   pmod[7] : pin 10 → HDA18 → B11
###############################################################################
set_property PACKAGE_PIN H12 [get_ports {pmod[0]}]  ;# PMOD pin 1
set_property PACKAGE_PIN E10 [get_ports {pmod[1]}]  ;# PMOD pin 2
set_property PACKAGE_PIN D10 [get_ports {pmod[2]}]  ;# PMOD pin 3
set_property PACKAGE_PIN C11 [get_ports {pmod[3]}]  ;# PMOD pin 4
set_property PACKAGE_PIN B10 [get_ports {pmod[4]}]  ;# PMOD pin 7
set_property PACKAGE_PIN E12 [get_ports {pmod[5]}]  ;# PMOD pin 8
set_property PACKAGE_PIN D11 [get_ports {pmod[6]}]  ;# PMOD pin 9
set_property PACKAGE_PIN B11 [get_ports {pmod[7]}]  ;# PMOD pin 10

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
