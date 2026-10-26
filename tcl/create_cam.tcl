# ============================================================
# KV260 camera capture, cam=rpi|ias|isp. Sourced by create_bd.tcl before the
# PS SmartConnect is built; appends its PS-side slaves to `slaves` and its
# interrupts to `irqs`.
#
#   clk_wiz_cam         pl_clk0 100 MHz -> 200 MHz (MIPI D-PHY reference)
#                       and 300 MHz (video clock)
#   mipi_csi2_rx_0      MIPI CSI-2 receiver with its D-PHY       0x8008_0000
#                         rpi: J9, 2 lanes, 912 Mb/s, RAW10 (IMX219)
#                         ias: J8, 4 lanes, 880 Mb/s, RAW10
#                         isp: J7 through the AP1302, 4 lanes, 1200 Mb/s,
#                              YUV 4:2:2 8-bit
#   cam_remap           AXI4-Stream subset converter: picks the 8 most
#                       significant bits of each RAW10 sample, or passes
#                       YUV 4:2:2 through, into the frame buffer writer's
#                       layout
#   v_frmbuf_wr_0       writes frames to DDR through S_AXI_HP0_FPD
#                                                                0x8009_0000
#                       raw cameras: Y8 (one byte per Bayer sample),
#                       isp: YUYV8
#   interrupts          CSI-2 receiver -> pl_ps_irq0[4], frame buffer -> [5]
#
# Pins: xdc/kv260_cam_<cam>.xdc (package pins + 100-ohm termination). The
# camera control pins and I2C come with iic=1, which cam= turns on.
# ============================================================

# Connector-specific settings: lanes, line rate (Mb/s), pixel format,
# frame buffer format, remap of the receiver's samples.
array set cam_cfg {
    rpi {2 912  RAW10      HAS_Y8   raw}
    ias {4 880  RAW10      HAS_Y8   raw}
    isp {4 1200 YUV422_8bit HAS_YUYV8 yuv}
}
lassign $cam_cfg($opt(cam)) cam_lanes cam_rate cam_fmt cam_fb_fmt cam_kind

# ---- Clocks: exact 200 MHz for the D-PHY, 300 MHz for the video path ----
create_bd_cell -type ip -vlnv [latest_ip clk_wiz] clk_wiz_cam
# The input frequency is left to propagate from pl_clk0, which is really
# 99.999001 MHz (IOPLL divider): any value typed in here differs from it and
# fails validation.
set_property -dict [list \
    CONFIG.PRIM_SOURCE                {No_buffer} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.CLKOUT2_USED               {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {300.000} \
    CONFIG.RESET_TYPE                 {ACTIVE_LOW} \
    CONFIG.RESET_PORT                 {resetn} \
] [get_bd_cells clk_wiz_cam]
connect_bd_net $clk [get_bd_pins clk_wiz_cam/clk_in1]
connect_bd_net [get_bd_pins $ps/pl_resetn0] [get_bd_pins clk_wiz_cam/resetn]
set cam_clk200 [get_bd_pins clk_wiz_cam/clk_out1]
set cam_vclk   [get_bd_pins clk_wiz_cam/clk_out2]

create_bd_cell -type ip -vlnv [latest_ip proc_sys_reset] rst_cam
connect_bd_net $cam_vclk [get_bd_pins rst_cam/slowest_sync_clk]
connect_bd_net [get_bd_pins $ps/pl_resetn0] [get_bd_pins rst_cam/ext_reset_in]
connect_bd_net [get_bd_pins clk_wiz_cam/locked] [get_bd_pins rst_cam/dcm_locked]
set cam_aresetn [get_bd_pins rst_cam/peripheral_aresetn]

# ---- MIPI CSI-2 receiver ----
create_bd_cell -type ip -vlnv [latest_ip mipi_csi2_rx_subsystem] mipi_csi2_rx_0
set_property -dict [list \
    CONFIG.CMN_NUM_LANES        $cam_lanes \
    CONFIG.C_DPHY_LANES         $cam_lanes \
    CONFIG.CMN_NUM_PIXELS       {1} \
    CONFIG.CMN_PXL_FORMAT       $cam_fmt \
    CONFIG.CMN_VC               {All} \
    CONFIG.CSI_BUF_DEPTH        {2048} \
    CONFIG.C_CSI_EN_ACTIVELANES {false} \
    CONFIG.C_CSI_EN_CRC         {true} \
    CONFIG.C_EN_CSI_V2_0        {false} \
    CONFIG.C_HS_LINE_RATE       $cam_rate \
    CONFIG.DPY_LINE_RATE        $cam_rate \
    CONFIG.C_HS_SETTLE_NS       {145} \
    CONFIG.DPY_EN_REG_IF        {true} \
    CONFIG.SupportLevel         {1} \
] [get_bd_cells mipi_csi2_rx_0]
# The bank is fixed by the pins; set it if this release still takes it.
catch { set_property CONFIG.HP_IO_BANK_SELECTION {66} [get_bd_cells mipi_csi2_rx_0] }
puts "INFO: create_cam: CSI-2 receiver: [get_property CONFIG.CMN_NUM_LANES [get_bd_cells mipi_csi2_rx_0]] lanes,\
 [get_property CONFIG.C_HS_LINE_RATE [get_bd_cells mipi_csi2_rx_0]] Mb/s, [get_property CONFIG.CMN_PXL_FORMAT [get_bd_cells mipi_csi2_rx_0]]"

create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:mipi_phy_rtl:1.0 mipi_cam
connect_bd_intf_net [get_bd_intf_ports mipi_cam] [get_bd_intf_pins mipi_csi2_rx_0/mipi_phy_if]
connect_bd_net $cam_clk200 [get_bd_pins mipi_csi2_rx_0/dphy_clk_200M]
connect_bd_net $cam_vclk   [get_bd_pins mipi_csi2_rx_0/video_aclk]
connect_bd_net $cam_aresetn [get_bd_pins mipi_csi2_rx_0/video_aresetn]
lappend slaves {mipi_csi2_rx_0/csirxss_s_axi 0x80080000 64K}
lappend irqs   {4 mipi_csi2_rx_0/csirxss_csi_irq}

# ---- Receiver samples -> frame buffer writer layout ----
create_bd_cell -type ip -vlnv [latest_ip axis_subset_converter] cam_remap
# The converter's input widths are only propagated at validation, but the
# remap strings are checked against them right away: copy them from the
# receiver's video output first.
set vo [get_bd_intf_pins mipi_csi2_rx_0/video_out]
set s_bytes [get_property CONFIG.TDATA_NUM_BYTES $vo]
set s_user  [get_property CONFIG.TUSER_WIDTH $vo]
puts "INFO: create_cam: receiver video_out: $s_bytes data bytes, tuser $s_user bits"
set_property -dict [list \
    CONFIG.S_TDATA_NUM_BYTES $s_bytes \
    CONFIG.S_TUSER_WIDTH     $s_user \
    CONFIG.S_HAS_TLAST       {1} \
] [get_bd_cells cam_remap]
connect_bd_intf_net $vo [get_bd_intf_pins cam_remap/S_AXIS]
connect_bd_net $cam_vclk    [get_bd_pins cam_remap/aclk]
connect_bd_net $cam_aresetn [get_bd_pins cam_remap/aresetn]
if {$cam_kind eq "raw"} {
    # RAW10, one sample per clock in tdata[9:0] -> Y8 in the first of three
    # 8-bit components.
    set_property -dict [list \
        CONFIG.M_TDATA_NUM_BYTES {3} \
        CONFIG.TDATA_REMAP       {16'b0000000000000000,tdata[9:2]} \
        CONFIG.M_HAS_TLAST       {1} \
        CONFIG.M_TUSER_WIDTH     {1} \
        CONFIG.TUSER_REMAP       {tuser[0:0]} \
        CONFIG.TLAST_REMAP       {tlast[0]} \
    ] [get_bd_cells cam_remap]
} else {
    # YUV 4:2:2, one sample per clock: tdata[15:0] = {C, Y} -> {0, C, Y}.
    set_property -dict [list \
        CONFIG.M_TDATA_NUM_BYTES {3} \
        CONFIG.TDATA_REMAP       {8'b00000000,tdata[15:0]} \
        CONFIG.M_HAS_TLAST       {1} \
        CONFIG.M_TUSER_WIDTH     {1} \
        CONFIG.TUSER_REMAP       {tuser[0:0]} \
        CONFIG.TLAST_REMAP       {tlast[0]} \
    ] [get_bd_cells cam_remap]
}

# ---- Frame buffer writer -> S_AXI_HP0_FPD -> DDR ----
create_bd_cell -type ip -vlnv [latest_ip v_frmbuf_wr] v_frmbuf_wr_0
set fb_cfg [list \
    CONFIG.SAMPLES_PER_CLOCK {1} \
    CONFIG.MAX_DATA_WIDTH    {8} \
    CONFIG.MAX_COLS          {1920} \
    CONFIG.MAX_ROWS          {1080} \
    CONFIG.AXIMM_DATA_WIDTH  {64} \
    CONFIG.MAX_NR_PLANES     {1} \
    CONFIG.HAS_RGB8          {0} \
    CONFIG.HAS_BGR8          {0} \
    CONFIG.HAS_RGBX8         {0} \
    CONFIG.HAS_YUVX8         {0} \
    CONFIG.HAS_YUYV8         {0} \
    CONFIG.HAS_Y_UV8         {0} \
    CONFIG.HAS_Y_UV8_420     {0} \
    CONFIG.HAS_Y8            {0} \
]
lappend fb_cfg CONFIG.$cam_fb_fmt {1}
set_property -dict $fb_cfg [get_bd_cells v_frmbuf_wr_0]
connect_bd_intf_net [get_bd_intf_pins cam_remap/M_AXIS] [get_bd_intf_pins v_frmbuf_wr_0/s_axis_video]
connect_bd_net $cam_vclk    [get_bd_pins v_frmbuf_wr_0/ap_clk]
connect_bd_net $cam_aresetn [get_bd_pins v_frmbuf_wr_0/ap_rst_n]
lappend slaves {v_frmbuf_wr_0/s_axi_CTRL 0x80090000 64K}
lappend irqs   {5 v_frmbuf_wr_0/interrupt}

set_property CONFIG.PSU__USE__S_AXI_GP2 {1} [get_bd_cells $ps]
create_bd_cell -type ip -vlnv [latest_ip smartconnect] axi_sc_hp0
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells axi_sc_hp0]
connect_bd_intf_net [get_bd_intf_pins v_frmbuf_wr_0/m_axi_mm_video] [get_bd_intf_pins axi_sc_hp0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_sc_hp0/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP0_FPD]
connect_bd_net $cam_vclk    [get_bd_pins axi_sc_hp0/aclk] [get_bd_pins $ps/saxihp0_fpd_aclk]
connect_bd_net $cam_aresetn [get_bd_pins axi_sc_hp0/aresetn]
