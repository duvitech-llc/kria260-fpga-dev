###############################################################################
# Raspberry Pi camera connector J9, MIPI CSI-2, 2 lanes (cam=rpi). Bank 66 (HP).
# Pins from kv260_carrier/2.0 board.xml (mipi_csi_raspi) and AMD's
# kv260_bist pin.xdc. The MIPI CSI-2 receiver in Vivado 2026.1 takes its pins
# from here, not from IP parameters.
###############################################################################
set_property PACKAGE_PIN D7 [get_ports mipi_cam_clk_p]
set_property PACKAGE_PIN D6 [get_ports mipi_cam_clk_n]
set_property PACKAGE_PIN E5 [get_ports {mipi_cam_data_p[0]}]
set_property PACKAGE_PIN D5 [get_ports {mipi_cam_data_n[0]}]
set_property PACKAGE_PIN G6 [get_ports {mipi_cam_data_p[1]}]
set_property PACKAGE_PIN F6 [get_ports {mipi_cam_data_n[1]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {mipi_cam_clk_p mipi_cam_clk_n mipi_cam_data_p[*] mipi_cam_data_n[*]}]
