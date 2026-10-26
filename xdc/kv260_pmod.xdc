###############################################################################
# PMOD J2 (bank 45, LVCMOS33), loaded with pmod=1.
#
# Two numbering schemes for the same connector:
#   Digilent PMOD: top row 1-6 (I/O 1-4, GND 5, 3V3 6), bottom row 7-12.
#   Carrier schematic (HDR_2X6_F_RA): odd 1,3,5,7 = top-row I/O,
#   even 2,4,6,8 = bottom-row I/O, 9/10 = GND, 11/12 = PMOD_3V3.
# PMOD 3V3 is switched and current limited (U42, TPS22948, 100 mA).
#
#   port     PMOD pin / J2 pin   net             package pin
#   pmod[0]  1  / 1              PMOD_HDA11      H12
#   pmod[1]  2  / 3              PMOD_HDA12      E10
#   pmod[2]  3  / 5              PMOD_HDA13      D10
#   pmod[3]  4  / 7              PMOD_HDA14      C11
#   pmod[4]  7  / 2              PMOD_HDA15      B10
#   pmod[5]  8  / 4              PMOD_HDA16_CC   E12  (clock capable)
#   pmod[6]  9  / 6              PMOD_HDA17      D11
#   pmod[7]  10 / 8              PMOD_HDA18      B11
# Verified against Kria-PYNQ kv260 base.xdc and AMD kv260_bist pin.xdc.
###############################################################################
set_property PACKAGE_PIN H12 [get_ports {pmod[0]}]
set_property PACKAGE_PIN E10 [get_ports {pmod[1]}]
set_property PACKAGE_PIN D10 [get_ports {pmod[2]}]
set_property PACKAGE_PIN C11 [get_ports {pmod[3]}]
set_property PACKAGE_PIN B10 [get_ports {pmod[4]}]
set_property PACKAGE_PIN E12 [get_ports {pmod[5]}]
set_property PACKAGE_PIN D11 [get_ports {pmod[6]}]
set_property PACKAGE_PIN B11 [get_ports {pmod[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {pmod[*]}]
set_property DRIVE 4             [get_ports {pmod[*]}]
set_property SLEW SLOW           [get_ports {pmod[*]}]
# Pull-ups so unconnected pins read 1 and the loopback test can find
# pins that are wired together.
set_property PULLUP true         [get_ports {pmod[*]}]
