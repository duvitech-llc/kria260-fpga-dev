###############################################################################
# IAS0 camera connector J7 through the AP1302 ISP, MIPI CSI-2, 4 lanes
# (cam=isp). Bank 66 (HP). Pins from kv260_carrier/2.0 board.xml
# (mipi_csi_isp) and AMD's kv260_bist pin.xdc.
###############################################################################
set_property PACKAGE_PIN G1 [get_ports mipi_cam_clk_p]
set_property PACKAGE_PIN F1 [get_ports mipi_cam_clk_n]
set_property PACKAGE_PIN E1 [get_ports {mipi_cam_data_p[0]}]
set_property PACKAGE_PIN D1 [get_ports {mipi_cam_data_n[0]}]
set_property PACKAGE_PIN F2 [get_ports {mipi_cam_data_p[1]}]
set_property PACKAGE_PIN E2 [get_ports {mipi_cam_data_n[1]}]
set_property PACKAGE_PIN G3 [get_ports {mipi_cam_data_p[2]}]
set_property PACKAGE_PIN F3 [get_ports {mipi_cam_data_n[2]}]
set_property PACKAGE_PIN E4 [get_ports {mipi_cam_data_p[3]}]
set_property PACKAGE_PIN E3 [get_ports {mipi_cam_data_n[3]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {mipi_cam_clk_p mipi_cam_clk_n mipi_cam_data_p[*] mipi_cam_data_n[*]}]
