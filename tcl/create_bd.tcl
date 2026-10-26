# ============================================================
# KV260 block design "system". Sourced by create_project.tcl.
#
# Always:
#   zynq_ultra_ps_e_0   PS (tcl/ps_config.tcl); pl_clk0 = 100 MHz clocks the PL.
#                       The KV260 has no PL oscillator, so the PS is in every
#                       design and must be initialised (psu_init) before the
#                       PL logic runs.
#   rst_pl_clk0         reset synchronised to pl_clk0
#   axi_sc_0            SmartConnect on M_AXI_HPM0_LPD (PS -> PL registers)
#   axi_bram_ctrl_0     8 KB scratch BRAM                        0x8000_0000
#   pl_clk / pl_rst     pl_clk0 and its synchronised reset (active high),
#                       exported for RTL in top.v
# fan=ps:
#   fan_slice           PS TTC0 waveform 0 (EMIO) -> fan_en_b (A12, active low)
# fan=rtl:
#   axi_gpio_fan        channel 1 (out) = fan_pwm control: bit 31 software
#                       control, bits 6..0 duty %; channel 2 (in) = duty in
#                       use                                      0x8002_0000
# pmod=1:
#   axi_gpio_pmod       PMOD J2, 8 pins, direction per pin       0x8001_0000
#                       (bit 0..3 = PMOD pins 1..4, bit 4..7 = pins 7..10;
#                       all inputs after reset)
# irq=1:
#   axi_timer_0         PL timer, interrupt -> pl_ps_irq0[0]     0x8003_0000
# dma=1:
#   axi_cdma_0          memory-to-memory DMA, control on HPM0_LPD, data
#                       through S_AXI_HP1_FPD into the DDR, interrupt ->
#                       pl_ps_irq0[1]                            0x8004_0000
# dp=1:
#   axi_gpio_dp         channel 1 (out) = dp_tpg control word, channel 2 (in) =
#                       frame counter                            0x8005_0000
#   vid_clk / vid_rst   PS video clock (dp_video_ref_clk, 74.25 MHz), also fed
#                       back as dp_video_in_clk; reset synchronised to it
#   vid_*               live-video input of the PS DisplayPort controller
# iic=1:
#   axi_iic_cam         camera I2C master (G11 SCL, F10 SDA) -> TCA9546 switch:
#                       ch0 AP1302 ISP (J7), ch1 IAS sensor (J8), ch2 RPi
#                       camera (J9); interrupt -> pl_ps_irq0[2] 0x8006_0000
#   axi_gpio_cam        4 outputs, all 0 after reset:           0x8007_0000
#                       bit 0 ap1302_rst_b (J11), bit 1 ap1302_standby (J10),
#                       bit 2 ias_xshutdown_b (K13), bit 3 rpi_cam_en (F11)
# cam=rpi|ias|isp:
#   MIPI CSI-2 camera capture into DDR, see tcl/create_cam.tcl: receiver
#   0x8008_0000 (irq 4), frame buffer writer 0x8009_0000 (irq 5).
# cpu=mbv:
#   MicroBlaze V co-processor, see tcl/create_mbv.tcl. PS side: its memory
#   0x8010_0000 (128 KB), mailbox 0x800A_0000 (interrupt pl_ps_irq0[3]),
#   run/reset control 0x800B_0000.
#
# PL interrupts: pl_ps_irq0[n] is GIC SPI 121 + n (interrupt ID 121 + n).
#
# Every PL slave gets a fixed address so bare-metal code can fall back to it
# when xparameters.h does not name it. The map is printed at the end.
# ============================================================

set ps "zynq_ultra_ps_e_0"

create_bd_design $bd_name
current_bd_design $bd_name

# ---- PS ----
create_bd_cell -type ip -vlnv [latest_ip zynq_ultra_ps_e] $ps
set_property -dict [ps_config] [get_bd_cells $ps]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "0"} [get_bd_cells $ps]

set clk [get_bd_pins $ps/pl_clk0]

create_bd_cell -type ip -vlnv [latest_ip proc_sys_reset] rst_pl_clk0
connect_bd_net $clk [get_bd_pins rst_pl_clk0/slowest_sync_clk]
connect_bd_net [get_bd_pins $ps/pl_resetn0] [get_bd_pins rst_pl_clk0/ext_reset_in]
set aresetn [get_bd_pins rst_pl_clk0/peripheral_aresetn]
connect_bd_net $clk [get_bd_pins $ps/maxihpm0_lpd_aclk]

# ---- AXI slaves on HPM0_LPD, each {interface-pin offset range} ----
set slaves {}

create_bd_cell -type ip -vlnv [latest_ip axi_bram_ctrl] axi_bram_ctrl_0
set_property -dict [list CONFIG.DATA_WIDTH {32} CONFIG.SINGLE_PORT_BRAM {1}] [get_bd_cells axi_bram_ctrl_0]
create_bd_cell -type ip -vlnv [latest_ip blk_mem_gen] bram_0
connect_bd_intf_net [get_bd_intf_pins axi_bram_ctrl_0/BRAM_PORTA] [get_bd_intf_pins bram_0/BRAM_PORTA]
lappend slaves {axi_bram_ctrl_0/S_AXI 0x80000000 8K}

if {$opt(pmod)} {
    create_bd_cell -type ip -vlnv [latest_ip axi_gpio] axi_gpio_pmod
    set_property -dict [list CONFIG.C_GPIO_WIDTH {8} CONFIG.C_ALL_INPUTS {0} CONFIG.C_ALL_OUTPUTS {0}] \
        [get_bd_cells axi_gpio_pmod]
    lappend slaves {axi_gpio_pmod/S_AXI 0x80010000 64K}
    create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 pmod
    connect_bd_intf_net [get_bd_intf_pins axi_gpio_pmod/GPIO] [get_bd_intf_ports pmod]
}

if {$opt(fan) eq "rtl"} {
    create_bd_cell -type ip -vlnv [latest_ip axi_gpio] axi_gpio_fan
    set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_OUTPUTS {1} \
                             CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH {7} CONFIG.C_ALL_INPUTS_2 {1}] \
        [get_bd_cells axi_gpio_fan]
    lappend slaves {axi_gpio_fan/S_AXI 0x80020000 64K}
    create_bd_port -dir O -from 31 -to 0 fan_ctrl_o
    connect_bd_net [get_bd_pins axi_gpio_fan/gpio_io_o] [get_bd_ports fan_ctrl_o]
    create_bd_port -dir I -from 6 -to 0 fan_duty_i
    connect_bd_net [get_bd_ports fan_duty_i] [get_bd_pins axi_gpio_fan/gpio2_io_i]
}

if {$opt(dp)} {
    create_bd_cell -type ip -vlnv [latest_ip axi_gpio] axi_gpio_dp
    set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_DOUT_DEFAULT {0x00000002} \
                             CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH {16} CONFIG.C_ALL_INPUTS_2 {1}] \
        [get_bd_cells axi_gpio_dp]
    lappend slaves {axi_gpio_dp/S_AXI 0x80050000 64K}
    create_bd_port -dir O -from 31 -to 0 dp_ctrl_o
    connect_bd_net [get_bd_pins axi_gpio_dp/gpio_io_o] [get_bd_ports dp_ctrl_o]
    create_bd_port -dir I -from 15 -to 0 dp_frames_i
    connect_bd_net [get_bd_ports dp_frames_i] [get_bd_pins axi_gpio_dp/gpio2_io_i]
}

# PL -> PS interrupts, in pl_ps_irq0 bit order: {bit pin}
set irqs {}

if {$opt(iic)} {
    create_bd_cell -type ip -vlnv [latest_ip axi_iic] axi_iic_cam
    # 400 kHz: the AP1302 firmware (about 150 KB) is loaded over this bus.
    set_property CONFIG.IIC_FREQ_KHZ {400} [get_bd_cells axi_iic_cam]
    lappend slaves {axi_iic_cam/S_AXI 0x80060000 64K}
    lappend irqs   {2 axi_iic_cam/iic2intc_irpt}
    create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 iic
    connect_bd_intf_net [get_bd_intf_pins axi_iic_cam/IIC] [get_bd_intf_ports iic]

    create_bd_cell -type ip -vlnv [latest_ip axi_gpio] axi_gpio_cam
    set_property -dict [list CONFIG.C_GPIO_WIDTH {4} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_DOUT_DEFAULT {0x00000000}] \
        [get_bd_cells axi_gpio_cam]
    lappend slaves {axi_gpio_cam/S_AXI 0x80070000 64K}
    create_bd_port -dir O -from 3 -to 0 cam_ctrl_o
    connect_bd_net [get_bd_pins axi_gpio_cam/gpio_io_o] [get_bd_ports cam_ctrl_o]
}

if {$opt(irq)} {
    create_bd_cell -type ip -vlnv [latest_ip axi_timer] axi_timer_0
    lappend slaves {axi_timer_0/S_AXI 0x80030000 64K}
    lappend irqs   {0 axi_timer_0/interrupt}
}

if {$opt(dma)} {
    create_bd_cell -type ip -vlnv [latest_ip axi_cdma] axi_cdma_0
    set_property -dict [list CONFIG.C_INCLUDE_SG {0} CONFIG.C_M_AXI_DATA_WIDTH {128} \
                             CONFIG.C_M_AXI_MAX_BURST_LEN {64} CONFIG.C_ADDR_WIDTH {40}] \
        [get_bd_cells axi_cdma_0]
    lappend slaves {axi_cdma_0/S_AXI_LITE 0x80040000 64K}
    lappend irqs   {1 axi_cdma_0/cdma_introut}
}

if {$opt(cpu) eq "mbv"} {
    source [file join $script_dir "create_mbv.tcl"]
}

if {$opt(cam) ne "none"} {
    source [file join $script_dir "create_cam.tcl"]
}

create_bd_cell -type ip -vlnv [latest_ip smartconnect] axi_sc_0
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI [llength $slaves]] [get_bd_cells axi_sc_0]
connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_HPM0_LPD] [get_bd_intf_pins axi_sc_0/S00_AXI]
connect_bd_net $clk     [get_bd_pins axi_sc_0/aclk]
connect_bd_net $aresetn [get_bd_pins axi_sc_0/aresetn]
if {$opt(cam) ne "none"} {
    # The frame buffer writer's control port runs on the 300 MHz video clock.
    set_property CONFIG.NUM_CLKS {2} [get_bd_cells axi_sc_0]
    connect_bd_net $cam_vclk [get_bd_pins axi_sc_0/aclk1]
}

# Connect each slave, and its still-open clock and reset inputs.
set i 0
foreach s $slaves {
    lassign $s pin off range
    set cell [get_bd_cells [lindex [split $pin /] 0]]
    connect_bd_intf_net [get_bd_intf_pins axi_sc_0/[format M%02d_AXI $i]] [get_bd_intf_pins $pin]
    foreach p [get_bd_pins -quiet -of_objects $cell -filter {TYPE == clk && DIR == I}] {
        if {[llength [get_bd_nets -quiet -of_objects $p]] == 0} { connect_bd_net $clk $p }
    }
    foreach p [get_bd_pins -quiet -of_objects $cell -filter {TYPE == rst && DIR == I}] {
        if {[llength [get_bd_nets -quiet -of_objects $p]] == 0} { connect_bd_net $aresetn $p }
    }
    incr i
}

# ---- DMA data path: CDMA master -> S_AXI_HP1_FPD -> DDR ----
if {$opt(dma)} {
    set_property CONFIG.PSU__USE__S_AXI_GP3 {1} [get_bd_cells $ps]
    create_bd_cell -type ip -vlnv [latest_ip smartconnect] axi_sc_hp1
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells axi_sc_hp1]
    connect_bd_intf_net [get_bd_intf_pins axi_cdma_0/M_AXI] [get_bd_intf_pins axi_sc_hp1/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins axi_sc_hp1/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP1_FPD]
    connect_bd_net $clk     [get_bd_pins axi_sc_hp1/aclk] [get_bd_pins $ps/saxihp1_fpd_aclk]
    connect_bd_net $aresetn [get_bd_pins axi_sc_hp1/aresetn]
}

# ---- DisplayPort live video ----
if {$opt(dp)} {
    set vclk [get_bd_pins $ps/dp_video_ref_clk]
    connect_bd_net $vclk [get_bd_pins $ps/dp_video_in_clk]
    create_bd_port -dir O -type clk vid_clk
    connect_bd_net $vclk [get_bd_ports vid_clk]
    create_bd_cell -type ip -vlnv [latest_ip proc_sys_reset] rst_vid
    connect_bd_net $vclk [get_bd_pins rst_vid/slowest_sync_clk]
    connect_bd_net [get_bd_pins $ps/pl_resetn0] [get_bd_pins rst_vid/ext_reset_in]
    create_bd_port -dir O -type rst vid_rst
    set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports vid_rst]
    connect_bd_net [get_bd_pins rst_vid/peripheral_reset] [get_bd_ports vid_rst]
    foreach {port pin width} {vid_pixel dp_live_video_in_pixel1 36 vid_hsync dp_live_video_in_hsync 1 \
                              vid_vsync dp_live_video_in_vsync 1 vid_de dp_live_video_in_de 1} {
        if {$width > 1} {
            create_bd_port -dir I -from [expr {$width - 1}] -to 0 $port
        } else {
            create_bd_port -dir I $port
        }
        connect_bd_net [get_bd_ports $port] [get_bd_pins $ps/$pin]
    }
}

# ---- PL -> PS interrupts ----
if {[llength $irqs] > 0} {
    set_property CONFIG.PSU__USE__IRQ0 {1} [get_bd_cells $ps]
    create_bd_cell -type ip -vlnv [latest_ip xlconcat] irq_concat
    set_property CONFIG.NUM_PORTS {8} [get_bd_cells irq_concat]
    foreach irq $irqs {
        lassign $irq bit pin
        connect_bd_net [get_bd_pins $pin] [get_bd_pins irq_concat/In$bit]
    }
    connect_bd_net [get_bd_pins irq_concat/dout] [get_bd_pins $ps/pl_ps_irq0]
}

# ---- PL clock and reset for RTL in top.v ----
create_bd_port -dir O -type clk pl_clk
connect_bd_net $clk [get_bd_ports pl_clk]
create_bd_port -dir O -type rst pl_rst
set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports pl_rst]
connect_bd_net [get_bd_pins rst_pl_clk0/peripheral_reset] [get_bd_ports pl_rst]

# ---- Fan: TTC0 waveform 0 via EMIO (as in AMD's Kria platforms) ----
if {$opt(fan) eq "ps"} {
    create_bd_cell -type ip -vlnv [latest_ip xlslice] fan_slice
    set_property -dict [list CONFIG.DIN_WIDTH {3} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0}] [get_bd_cells fan_slice]
    connect_bd_net [get_bd_pins $ps/emio_ttc0_wave_o] [get_bd_pins fan_slice/Din]
    create_bd_port -dir O -from 0 -to 0 fan_en_b
    connect_bd_net [get_bd_pins fan_slice/Dout] [get_bd_ports fan_en_b]
}

# ---- Address map (fixed) ----
foreach s $slaves {
    lassign $s pin off range
    assign_bd_address -target_address_space [get_bd_addr_spaces $ps/Data] \
        -offset $off -range $range [get_bd_addr_segs -of_objects [get_bd_intf_pins $pin]]
}
# Everything else (the CDMA's view of the DDR through HP1: low DDR at 0, the
# same addresses the A53 uses) is assigned automatically.
assign_bd_address
if {$opt(dma)} {
    puts "INFO: Address map seen by axi_cdma_0:"
    foreach seg [lsort [get_bd_addr_segs -of_objects [get_bd_addr_spaces axi_cdma_0/Data]]] {
        puts [format "INFO:   %-50s 0x%010lX  %s" [get_property NAME $seg] [get_property OFFSET $seg] [get_property RANGE $seg]]
    }
}

# ---- Validate, save, wrap ----
validate_bd_design
save_bd_design
set bd_file [get_files ${bd_name}.bd]
generate_target all $bd_file
add_files -norecurse [make_wrapper -files $bd_file -top]

puts "INFO: Block design '$bd_name' created. Address map seen by the PS:"
foreach seg [lsort [get_bd_addr_segs -of_objects [get_bd_addr_spaces $ps/Data]]] {
    puts [format "INFO:   %-50s 0x%08X  %s" [get_property NAME $seg] [get_property OFFSET $seg] [get_property RANGE $seg]]
}
if {$opt(cpu) eq "mbv"} {
    puts "INFO: Address map seen by the MicroBlaze V co-processor:"
    foreach seg [lsort [get_bd_addr_segs -of_objects [get_bd_addr_spaces microblaze_riscv_0/*]]] {
        puts [format "INFO:   %-50s 0x%08X  %s" [get_property NAME $seg] [get_property OFFSET $seg] [get_property RANGE $seg]]
    }
}
