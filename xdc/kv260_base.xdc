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
# User LEDs (Bank 46, LVCMOS33, Active-HIGH)
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
# Raspberry Pi 40-pin Header (J2) – Bank 45, LVCMOS33
# Uncomment and adjust if connecting PL logic to this expansion header.
# Pin mappings depend on SoM/carrier revision; verify against UG1089 Table 28.
###############################################################################
# set_property PACKAGE_PIN ... [get_ports rpi_io[*]]
# set_property IOSTANDARD LVCMOS33 [get_ports rpi_io[*]]

###############################################################################
# IAS Camera Connector (J3/J4) – HP banks, MIPI DPHY
# MIPI CSI-2 data lanes are constrained via the MIPI DPHY IP, not here.
# Control signals (I2C, GPIO, power) are on PS MIO or HP bank I/O.
###############################################################################

###############################################################################
# End of KV260 Constraints
###############################################################################
