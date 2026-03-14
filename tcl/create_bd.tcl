# ============================================================
# KV260 Zynq UltraScale+ PS <-> PL AXI Base Design
# Vivado 2025.2  –  K26 SoM (XCK26-SFVC784-2LV-C)
#
# Block Design contents:
#   - zynq_ultra_ps_e_0     : PS (K26 SoM configuration)
#   - rst_pl_clk0           : Synchronized reset
#   - axi_sc_0              : SmartConnect  1SI → 2MI
#   - axi_bram_ctrl_0       : AXI BRAM Controller
#   - bram_0                : Block RAM (8KB)
#   - axi_gpio_0            : AXI GPIO 4-bit output → LEDs
# ============================================================

set bd_name  "zynq_bd"
set ps_name  "zynq_ultra_ps_e_0"
set rst_name "rst_pl_clk0"

# ----
# Create BD
# ----
if {[llength [get_bd_designs -quiet $bd_name]] == 0} {
    create_bd_design $bd_name
}
current_bd_design $bd_name

# ----
# Create Zynq MPSoC PS
# ----
if {[llength [get_bd_cells -quiet $ps_name]] == 0} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 $ps_name
}

# ----
# PS Configuration – K26 SoM peripheral mapping
# Based on KV260 Starter Kit board preset (ug1089 / XilinxBoardStore 1.4)
# ----
set_property -dict [list \
    \
    CONFIG.PSU__DDRC__MEMORY_TYPE              {DDR 4}                 \
    CONFIG.PSU__DDRC__DEVICE_CAPACITY          {8192 MBits}            \
    CONFIG.PSU__DDRC__DRAM_WIDTH               {16 Bits}               \
    CONFIG.PSU__DDRC__BUS_WIDTH                {64 Bit}                \
    CONFIG.PSU__DDRC__ROW_ADDR_COUNT           {16}                    \
    CONFIG.PSU__DDRC__SPEED_BIN                {DDR4_2400R}            \
    CONFIG.PSU__DDRC__ECC                      {Disabled}              \
    CONFIG.PSU__DDRC__VREF                     {1}                     \
    CONFIG.PSU__DDRC__CL                       {16}                    \
    CONFIG.PSU__DDRC__CWL                      {14}                    \
    CONFIG.PSU__DDRC__DM_DBI                   {DM_NO_DBI}             \
    \
    CONFIG.PSU__QSPI__PERIPHERAL__ENABLE       {1}                     \
    CONFIG.PSU__QSPI__PERIPHERAL__MODE         {Single}                \
    CONFIG.PSU__QSPI__PERIPHERAL__DATA_MODE    {x4}                    \
    CONFIG.PSU__QSPI__PERIPHERAL__IO           {MIO 0 .. 5}            \
    CONFIG.PSU__QSPI__GRP_FBCLK__ENABLE        {0}                     \
    \
    CONFIG.PSU__I2C1__PERIPHERAL__ENABLE       {1}                     \
    CONFIG.PSU__I2C1__PERIPHERAL__IO           {MIO 24 .. 25}          \
    \
    CONFIG.PSU__UART1__PERIPHERAL__ENABLE      {1}                     \
    CONFIG.PSU__UART1__PERIPHERAL__IO          {MIO 36 .. 37}          \
    \
    CONFIG.PSU__SD1__PERIPHERAL__ENABLE        {1}                     \
    CONFIG.PSU__SD1__SLOT_TYPE                 {SD 3.0}                \
    CONFIG.PSU__SD1__PERIPHERAL__IO            {MIO 39 .. 51}          \
    CONFIG.PSU__SD1__DATA_TRANSFER_MODE        {8Bit}                  \
    CONFIG.PSU__SD1__GRP_CD__ENABLE            {1}                     \
    CONFIG.PSU__SD1__GRP_CD__IO                {MIO 45}                \
    CONFIG.PSU__SD1__GRP_POW__ENABLE           {1}                     \
    CONFIG.PSU__SD1__GRP_POW__IO               {MIO 43}                \
    \
    CONFIG.PSU__USB0__PERIPHERAL__ENABLE       {1}                     \
    CONFIG.PSU__USB0__PERIPHERAL__IO           {MIO 52 .. 63}          \
    CONFIG.PSU__USB0__REF_CLK_SEL              {Ref Clk1}              \
    CONFIG.PSU__USB0__REF_CLK_FREQ             {26}                    \
    CONFIG.PSU__USB0__RESET__ENABLE            {1}                     \
    CONFIG.PSU__USB__RESET__MODE               {Boot Pin}              \
    CONFIG.PSU__USB3_0__PERIPHERAL__ENABLE     {1}                     \
    CONFIG.PSU__USB3_0__PERIPHERAL__IO         {GT Lane2}              \
    \
    CONFIG.PSU__ENET3__PERIPHERAL__ENABLE      {1}                     \
    CONFIG.PSU__ENET3__PERIPHERAL__IO          {MIO 64 .. 75}          \
    CONFIG.PSU__ENET3__GRP_MDIO__ENABLE        {1}                     \
    CONFIG.PSU__ENET3__GRP_MDIO__IO            {MIO 76 .. 77}          \
    \
    CONFIG.PSU__DISPLAYPORT__PERIPHERAL__ENABLE {1}                    \
    CONFIG.PSU__DISPLAYPORT__LANE0__ENABLE      {1}                    \
    CONFIG.PSU__DISPLAYPORT__LANE0__IO          {GT Lane1}             \
    CONFIG.PSU__DISPLAYPORT__LANE1__ENABLE      {1}                    \
    CONFIG.PSU__DISPLAYPORT__LANE1__IO          {GT Lane0}             \
    \
    CONFIG.PSU__TTC0__PERIPHERAL__ENABLE       {1}                     \
    CONFIG.PSU__TTC1__PERIPHERAL__ENABLE       {1}                     \
    CONFIG.PSU__TTC2__PERIPHERAL__ENABLE       {1}                     \
    CONFIG.PSU__TTC3__PERIPHERAL__ENABLE       {1}                     \
    \
    CONFIG.PSU__SWDT0__PERIPHERAL__ENABLE      {1}                     \
    CONFIG.PSU__SWDT1__PERIPHERAL__ENABLE      {1}                     \
    \
    CONFIG.PSU__GPIO0_MIO__PERIPHERAL__ENABLE  {1}                     \
    CONFIG.PSU__GPIO0_MIO__IO                  {MIO 0 .. 25}           \
    CONFIG.PSU__GPIO1_MIO__PERIPHERAL__ENABLE  {1}                     \
    CONFIG.PSU__GPIO1_MIO__IO                  {MIO 26 .. 51}          \
    \
    CONFIG.PSU_BANK_0_IO_STANDARD              {LVCMOS18}              \
    CONFIG.PSU_BANK_1_IO_STANDARD              {LVCMOS18}              \
    CONFIG.PSU_BANK_2_IO_STANDARD              {LVCMOS18}              \
    CONFIG.PSU_BANK_3_IO_STANDARD              {LVCMOS18}              \
    \
    CONFIG.PSU__FPGA_PL0_ENABLE                {1}                     \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__SRCSEL  {IOPLL}                 \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100}                   \
    CONFIG.PSU__CRF_APB__DDR_CTRL__FREQMHZ     {1200}                  \
    CONFIG.PSU__CRF_APB__ACPU_CTRL__FREQMHZ    {1333.333}              \
    CONFIG.PSU__CRL_APB__CPU_R5_CTRL__FREQMHZ  {533.333}               \
    CONFIG.PSU__CRF_APB__GPU_REF_CTRL__FREQMHZ {600}                   \
    CONFIG.PSU__CRF_APB__DP_VIDEO_REF_CTRL__SRCSEL {VPLL}              \
    CONFIG.PSU__CRF_APB__DP_AUDIO_REF_CTRL__SRCSEL {RPLL}              \
    CONFIG.PSU__CRF_APB__DP_STC_REF_CTRL__SRCSEL   {RPLL}              \
    CONFIG.PSU__CRL_APB__GEM3_REF_CTRL__SRCSEL {IOPLL}                 \
    CONFIG.PSU__CRL_APB__GEM3_REF_CTRL__FREQMHZ {125}                  \
    CONFIG.PSU__CRL_APB__USB0_BUS_REF_CTRL__SRCSEL  {IOPLL}            \
    CONFIG.PSU__CRL_APB__USB0_BUS_REF_CTRL__FREQMHZ {250}              \
    CONFIG.PSU__CRL_APB__UART1_REF_CTRL__SRCSEL {IOPLL}                \
    CONFIG.PSU__CRL_APB__UART1_REF_CTRL__FREQMHZ {100}                 \
    CONFIG.PSU__CRL_APB__I2C1_REF_CTRL__SRCSEL {IOPLL}                 \
    CONFIG.PSU__CRL_APB__I2C1_REF_CTRL__FREQMHZ {100}                  \
    CONFIG.PSU__CRL_APB__QSPI_REF_CTRL__SRCSEL {IOPLL}                 \
    CONFIG.PSU__CRL_APB__QSPI_REF_CTRL__FREQMHZ {125}                  \
] [get_bd_cells $ps_name]

# ----
# Apply PS automation (wires DDR, FIXED_IO without board preset)
# ----
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "0"} \
    [get_bd_cells $ps_name]

# ----
# Reset – synchronized to pl_clk0
# ----
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 $rst_name

connect_bd_net \
    [get_bd_pins $ps_name/pl_clk0] \
    [get_bd_pins $rst_name/slowest_sync_clk]

connect_bd_net \
    [get_bd_pins $ps_name/pl_resetn0] \
    [get_bd_pins $rst_name/ext_reset_in]

# ----
# SmartConnect  1SI → 2MI  (M_AXI_HPM0_LPD master)
# ----
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_sc_0
set_property CONFIG.NUM_MI 2 [get_bd_cells axi_sc_0]
set_property CONFIG.NUM_SI 1 [get_bd_cells axi_sc_0]

# ----
# AXI BRAM Controller + Block RAM
# ----
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_0
set_property -dict [list \
    CONFIG.DATA_WIDTH 32 \
    CONFIG.SINGLE_PORT_BRAM 1 \
] [get_bd_cells axi_bram_ctrl_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 bram_0

# ----
# AXI GPIO – 4-bit pure output → carrier card LEDs
# No push buttons on KV260 PL; use PS GPIO MIO for inputs if needed.
# ----
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH  4 \
    CONFIG.C_ALL_OUTPUTS 1 \
] [get_bd_cells axi_gpio_0]

# ----
# AXI interface connections
# ----
connect_bd_intf_net \
    [get_bd_intf_pins $ps_name/M_AXI_HPM0_LPD] \
    [get_bd_intf_pins axi_sc_0/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins axi_sc_0/M00_AXI] \
    [get_bd_intf_pins axi_bram_ctrl_0/S_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins axi_sc_0/M01_AXI] \
    [get_bd_intf_pins axi_gpio_0/S_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins axi_bram_ctrl_0/BRAM_PORTA] \
    [get_bd_intf_pins bram_0/BRAM_PORTA]

# ----
# Clocking – all fabric IP driven by pl_clk0 (100 MHz)
# ----
connect_bd_net \
    [get_bd_pins $ps_name/pl_clk0] \
    [get_bd_pins $ps_name/maxihpm0_lpd_aclk] \
    [get_bd_pins axi_sc_0/aclk] \
    [get_bd_pins axi_bram_ctrl_0/s_axi_aclk] \
    [get_bd_pins axi_gpio_0/s_axi_aclk]

# ----
# Reset – synchronized peripheral reset
# ----
connect_bd_net \
    [get_bd_pins $rst_name/peripheral_aresetn] \
    [get_bd_pins axi_sc_0/aresetn] \
    [get_bd_pins axi_bram_ctrl_0/s_axi_aresetn] \
    [get_bd_pins axi_gpio_0/s_axi_aresetn]

# ----
# Export GPIO output port to top level
# (output only – no gpio_io_i since C_ALL_OUTPUTS=1)
# ----
make_bd_pins_external [get_bd_pins axi_gpio_0/gpio_io_o]

# ----
# Address map – MUST be called after all AXI slaves are instantiated
# ----
assign_bd_address

# ----
# Validate & Save
# ----
validate_bd_design
save_bd_design

# ----
# Generate wrapper and set as top for synthesis
# ----
set wrapper_files [make_wrapper -files [get_files ${bd_name}.bd] -top]
add_files -norecurse $wrapper_files
set_property top ${bd_name}_wrapper [current_fileset]

puts "INFO: KV260 base block design validated and saved"
