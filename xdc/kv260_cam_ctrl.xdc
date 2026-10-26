###############################################################################
# Camera I2C and camera control pins (iic=1), bank 45, LVCMOS33.
#
# I2C: HDA I2C to the TCA9546 switch on the carrier (som240_1_d16/d17):
#   ch0 AP1302 ISP + AR1335 module (IAS0, J7)
#   ch1 IAS1 sensor (J8)
#   ch2 Raspberry Pi camera (J9)
# The carrier has pull-ups on the bus; the internal ones are added for when
# no switch channel is selected.
#
# Control (AMD kv260_bist pin.xdc):
#   cam_ctrl[0] ap1302_rst_b      J11  HDA02  ISP reset, active low
#   cam_ctrl[1] ap1302_standby    J10  HDA03  ISP standby, active high
#   cam_ctrl[2] ias_xshutdown_b   K13  HDA04  IAS1 (J8) sensor shutdown, active low
#   cam_ctrl[3] rpi_cam_en        F11  HDA09  RPi camera (J9) power enable
###############################################################################
set_property PACKAGE_PIN G11 [get_ports iic_scl]
set_property PACKAGE_PIN F10 [get_ports iic_sda]
set_property IOSTANDARD LVCMOS33 [get_ports {iic_scl iic_sda}]
set_property DRIVE 4             [get_ports {iic_scl iic_sda}]
set_property SLEW SLOW           [get_ports {iic_scl iic_sda}]
set_property PULLUP true         [get_ports {iic_scl iic_sda}]

set_property PACKAGE_PIN J11 [get_ports {cam_ctrl[0]}]
set_property PACKAGE_PIN J10 [get_ports {cam_ctrl[1]}]
set_property PACKAGE_PIN K13 [get_ports {cam_ctrl[2]}]
set_property PACKAGE_PIN F11 [get_ports {cam_ctrl[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_ctrl[*]}]
set_property DRIVE 4             [get_ports {cam_ctrl[*]}]
set_property SLEW SLOW           [get_ports {cam_ctrl[*]}]
