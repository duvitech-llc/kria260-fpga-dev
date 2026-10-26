# ============================================================
# KV260 MicroBlaze V (RISC-V) co-processor, cpu=mbv. Sourced by create_bd.tcl
# before the PS SmartConnect is built; it appends its PS-side slaves to
# `slaves` and its interrupt to `irqs`.
#
#   microblaze_riscv_0  RV32IMC, 100 MHz (pl_clk0), interrupts, debug (MDM)
#   mbv_lmb_ctrl        one LMB controller serving both the instruction and
#                       the data LMB (C_NUM_LMB = 2) on port A of mbv_bram
#   mbv_bram            128 KB true dual-port block RAM: the co-processor's
#                       whole memory, at 0x0000_0000 for it
#   mbv_bram_ps         port B of mbv_bram on the PS bus        0x8010_0000
#                       (the A53 writes the program and the data here)
#   mbv_mailbox         AMD mailbox: S0 on the PS bus           0x800A_0000
#                       S1 on the co-processor bus              0x4000_0000
#                       Interrupt_0 -> PS (pl_ps_irq0[3]),
#                       Interrupt_1 -> mbv_intc
#   mbv_intc            AXI interrupt controller of the co-processor
#                                                               0x4100_0000
#   axi_gpio_mbv        bit 0 = run: 0 holds the co-processor in reset (the
#                       state after the PL is loaded)           0x800B_0000
#   mdm_riscv_0         debug module: xsdb sees the core over the same JTAG
#   rst_mbv             reset of the co-processor domain
#
# Hand-built rather than with the MicroBlaze V block automation, because the
# automation gives each LMB its own controller and so uses both BRAM ports,
# leaving none for the PS.
# ============================================================

set cpu microblaze_riscv_0

# ---- CPU ----
create_bd_cell -type ip -vlnv [latest_ip microblaze_riscv] $cpu
set_property -dict [list \
    CONFIG.C_USE_MULDIV      {1} \
    CONFIG.C_USE_COMPRESSION {1} \
    CONFIG.C_D_AXI           {1} \
    CONFIG.C_I_LMB           {1} \
    CONFIG.C_D_LMB           {1} \
    CONFIG.C_USE_INTERRUPT   {1} \
    CONFIG.C_DEBUG_ENABLED   {1} \
    CONFIG.C_BASE_VECTORS    {0x0000000000000000} \
] [get_bd_cells $cpu]

create_bd_cell -type ip -vlnv [latest_ip mdm_riscv] mdm_riscv_0
connect_bd_intf_net [get_bd_intf_pins mdm_riscv_0/MBDEBUG_0] [get_bd_intf_pins $cpu/DEBUG]

# ---- Reset: pl_resetn0, and the PS-controlled run bit ----
create_bd_cell -type ip -vlnv [latest_ip axi_gpio] axi_gpio_mbv
set_property -dict [list CONFIG.C_GPIO_WIDTH {1} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_DOUT_DEFAULT {0x00000000}] \
    [get_bd_cells axi_gpio_mbv]
lappend slaves {axi_gpio_mbv/S_AXI 0x800B0000 64K}

create_bd_cell -type ip -vlnv [latest_ip proc_sys_reset] rst_mbv
connect_bd_net $clk [get_bd_pins rst_mbv/slowest_sync_clk]
connect_bd_net [get_bd_pins $ps/pl_resetn0] [get_bd_pins rst_mbv/ext_reset_in]
# aux_reset_in is active low: run = 0 keeps the co-processor in reset.
connect_bd_net [get_bd_pins axi_gpio_mbv/gpio_io_o] [get_bd_pins rst_mbv/aux_reset_in]
connect_bd_net [get_bd_pins mdm_riscv_0/Debug_SYS_Rst] [get_bd_pins rst_mbv/mb_debug_sys_rst]
connect_bd_net [get_bd_pins rst_mbv/mb_reset] [get_bd_pins $cpu/Reset]
connect_bd_net $clk [get_bd_pins $cpu/Clk]
set mbv_aresetn [get_bd_pins rst_mbv/peripheral_aresetn]
set mbv_busrst  [get_bd_pins rst_mbv/bus_struct_reset]

# ---- Local memory: 128 KB, one controller for both LMBs, port B for the PS ----
foreach lmb {ilmb dlmb} {
    create_bd_cell -type ip -vlnv [latest_ip lmb_v10] mbv_$lmb
    connect_bd_net $clk     [get_bd_pins mbv_$lmb/LMB_Clk]
    connect_bd_net $mbv_busrst [get_bd_pins mbv_$lmb/SYS_Rst]
}
connect_bd_intf_net [get_bd_intf_pins $cpu/ILMB] [get_bd_intf_pins mbv_ilmb/LMB_M]
connect_bd_intf_net [get_bd_intf_pins $cpu/DLMB] [get_bd_intf_pins mbv_dlmb/LMB_M]

create_bd_cell -type ip -vlnv [latest_ip lmb_bram_if_cntlr] mbv_lmb_ctrl
set_property CONFIG.C_NUM_LMB {2} [get_bd_cells mbv_lmb_ctrl]
connect_bd_intf_net [get_bd_intf_pins mbv_dlmb/LMB_Sl_0] [get_bd_intf_pins mbv_lmb_ctrl/SLMB]
connect_bd_intf_net [get_bd_intf_pins mbv_ilmb/LMB_Sl_0] [get_bd_intf_pins mbv_lmb_ctrl/SLMB1]
connect_bd_net $clk        [get_bd_pins mbv_lmb_ctrl/LMB_Clk]
connect_bd_net $mbv_busrst [get_bd_pins mbv_lmb_ctrl/LMB_Rst]

create_bd_cell -type ip -vlnv [latest_ip blk_mem_gen] mbv_bram
set_property -dict [list CONFIG.Memory_Type {True_Dual_Port_RAM}] [get_bd_cells mbv_bram]
connect_bd_intf_net [get_bd_intf_pins mbv_lmb_ctrl/BRAM_PORT] [get_bd_intf_pins mbv_bram/BRAM_PORTA]

create_bd_cell -type ip -vlnv [latest_ip axi_bram_ctrl] mbv_bram_ps
set_property -dict [list CONFIG.DATA_WIDTH {32} CONFIG.SINGLE_PORT_BRAM {1}] [get_bd_cells mbv_bram_ps]
connect_bd_intf_net [get_bd_intf_pins mbv_bram_ps/BRAM_PORTA] [get_bd_intf_pins mbv_bram/BRAM_PORTB]
lappend slaves {mbv_bram_ps/S_AXI 0x80100000 128K}

# ---- Mailbox between the A53 (S0) and the co-processor (S1) ----
create_bd_cell -type ip -vlnv [latest_ip mailbox] mbv_mailbox
set_property CONFIG.C_ASYNC_CLKS {0} [get_bd_cells mbv_mailbox]
lappend slaves {mbv_mailbox/S0_AXI 0x800A0000 64K}
lappend irqs   {3 mbv_mailbox/Interrupt_0}

# ---- Co-processor peripheral bus: mailbox S1, interrupt controller ----
create_bd_cell -type ip -vlnv [latest_ip axi_intc] mbv_intc
set_property CONFIG.C_IRQ_CONNECTION {0} [get_bd_cells mbv_intc]
connect_bd_intf_net [get_bd_intf_pins mbv_intc/interrupt] [get_bd_intf_pins $cpu/INTERRUPT]
connect_bd_net [get_bd_pins mbv_mailbox/Interrupt_1] [get_bd_pins mbv_intc/intr]

create_bd_cell -type ip -vlnv [latest_ip smartconnect] axi_sc_mbv
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] [get_bd_cells axi_sc_mbv]
connect_bd_intf_net [get_bd_intf_pins $cpu/M_AXI_DP]      [get_bd_intf_pins axi_sc_mbv/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_sc_mbv/M00_AXI] [get_bd_intf_pins mbv_mailbox/S1_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_sc_mbv/M01_AXI] [get_bd_intf_pins mbv_intc/s_axi]
connect_bd_net $clk [get_bd_pins axi_sc_mbv/aclk] [get_bd_pins mbv_mailbox/S1_AXI_ACLK] [get_bd_pins mbv_intc/s_axi_aclk]
connect_bd_net $mbv_aresetn [get_bd_pins axi_sc_mbv/aresetn] [get_bd_pins mbv_intc/s_axi_aresetn]
# The mailbox stays out of reset while the co-processor is held: with its S1
# reset on the co-processor's reset, the whole mailbox is in reset, the A53's
# accesses to S0 never complete, and they block the PS SmartConnect (found
# on the board, 2026-10-26).
connect_bd_net $aresetn [get_bd_pins mbv_mailbox/S1_AXI_ARESETN]

# ---- Co-processor address map (its own address spaces) ----
set mbv_data [get_bd_addr_spaces $cpu/Data]
set mbv_inst [get_bd_addr_spaces $cpu/Instruction]
assign_bd_address -target_address_space $mbv_data -offset 0x00000000 -range 128K \
    [get_bd_addr_segs -of_objects [get_bd_intf_pins mbv_lmb_ctrl/SLMB]]
assign_bd_address -target_address_space $mbv_inst -offset 0x00000000 -range 128K \
    [get_bd_addr_segs -of_objects [get_bd_intf_pins mbv_lmb_ctrl/SLMB1]]
assign_bd_address -target_address_space $mbv_data -offset 0x40000000 -range 64K \
    [get_bd_addr_segs -of_objects [get_bd_intf_pins mbv_mailbox/S1_AXI]]
assign_bd_address -target_address_space $mbv_data -offset 0x41000000 -range 64K \
    [get_bd_addr_segs -of_objects [get_bd_intf_pins mbv_intc/s_axi]]
