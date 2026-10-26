###############################################################################
# DisplayPort live video (dp=1). No package pins: the PL test pattern goes to
# the PS DisplayPort controller inside the device.
#
# The PS IP declares a clock only for pl_clk0, not for its video clock output
# (PS8 pin DPVIDEOREFCLK, then BUFG_PS -> dp_video_ref_clk), so it is
# declared here: 74.25 MHz for 1280x720 at 60 Hz (VPLL, set in
# tcl/ps_config.tcl; software sets the same rate). Without it the pattern
# generator is not timed at all.
###############################################################################
create_clock -name vid_clk -period 13.468 \
    [get_pins -hierarchical -filter {NAME =~ */zynq_ultra_ps_e_0/inst/PS8_i/DPVIDEOREFCLK}]

# The processor's control word (pl_clk0) is synchronised into vid_clk in
# dp_tpg.v, and the frame counter comes back through a synchroniser in
# top.v. Both carry quasi-static values.
set_clock_groups -asynchronous -group [get_clocks clk_pl_0] -group [get_clocks vid_clk]
