###############################################################################
# IAS1 camera connector J8, MIPI CSI-2, 4 lanes, straight to the PL (cam=ias).
# Bank 66 (HP). Pins from kv260_carrier/2.0 board.xml (mipi_csi_ias) and
# AMD's kv260_bist pin.xdc.
###############################################################################
set_property PACKAGE_PIN C1 [get_ports mipi_cam_clk_p]
set_property PACKAGE_PIN B1 [get_ports mipi_cam_clk_n]
set_property PACKAGE_PIN A2 [get_ports {mipi_cam_data_p[0]}]
set_property PACKAGE_PIN A1 [get_ports {mipi_cam_data_n[0]}]
set_property PACKAGE_PIN B3 [get_ports {mipi_cam_data_p[1]}]
set_property PACKAGE_PIN A3 [get_ports {mipi_cam_data_n[1]}]
set_property PACKAGE_PIN B4 [get_ports {mipi_cam_data_p[2]}]
set_property PACKAGE_PIN A4 [get_ports {mipi_cam_data_n[2]}]
set_property PACKAGE_PIN D4 [get_ports {mipi_cam_data_p[3]}]
set_property PACKAGE_PIN C4 [get_ports {mipi_cam_data_n[3]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {mipi_cam_clk_p mipi_cam_clk_n mipi_cam_data_p[*] mipi_cam_data_n[*]}]
