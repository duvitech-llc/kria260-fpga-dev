# ============================================================
# KV260: Zynq UltraScale+ PS configuration for the K26 SoM on the KV260
# carrier. Sourced by create_bd.tcl; [ps_config] returns the CONFIG list.
#
# Hand-configured on purpose (no board preset): the KV260 board files are
# not part of a plain Vivado install, and the preset DDR4 timing (CWL=14)
# is rejected by Vivado 2026.1, which only accepts {12,16} for DDR4-2400.
# MIO and GT lane assignments follow kv260_carrier/2.0 preset.xml.
# ============================================================

proc ps_config {} {
    global opt
    set cfg [list \
        CONFIG.PSU__DDRC__MEMORY_TYPE              {DDR 4}                 \
        CONFIG.PSU__DDRC__DEVICE_CAPACITY          {8192 MBits}            \
        CONFIG.PSU__DDRC__DRAM_WIDTH               {16 Bits}               \
        CONFIG.PSU__DDRC__BUS_WIDTH                {64 Bit}                \
        CONFIG.PSU__DDRC__ROW_ADDR_COUNT           {16}                    \
        CONFIG.PSU__DDRC__BG_ADDR_COUNT            {1}                     \
        CONFIG.PSU__DDRC__SPEED_BIN                {DDR4_2400R}            \
        CONFIG.PSU__DDRC__ECC                      {Disabled}              \
        CONFIG.PSU__DDRC__VREF                     {1}                     \
        CONFIG.PSU__DDRC__CL                       {16}                    \
        CONFIG.PSU__DDRC__CWL                      {16}                    \
        CONFIG.PSU__DDRC__T_RCD                    {16}                    \
        CONFIG.PSU__DDRC__T_RP                     {16}                    \
        CONFIG.PSU__DDRC__T_RC                     {47.06}                 \
        CONFIG.PSU__DDRC__T_RAS_MIN                {33}                    \
        CONFIG.PSU__DDRC__T_FAW                    {30.0}                  \
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
        CONFIG.PSU__DP__LANE_SEL                    {Dual Lower}           \
        CONFIG.PSU__DISPLAYPORT__LANE0__ENABLE      {1}                    \
        CONFIG.PSU__DISPLAYPORT__LANE0__IO          {GT Lane1}             \
        CONFIG.PSU__DISPLAYPORT__LANE1__ENABLE      {1}                    \
        CONFIG.PSU__DISPLAYPORT__LANE1__IO          {GT Lane0}             \
        CONFIG.PSU__DPAUX__PERIPHERAL__ENABLE       {1}                    \
        CONFIG.PSU__DPAUX__PERIPHERAL__IO           {MIO 27 .. 30}         \
        CONFIG.PSU__DP__REF_CLK_SEL                 {Ref Clk0}             \
        CONFIG.PSU__DP__REF_CLK_FREQ                {27}                   \
        \
        CONFIG.PSU__TTC0__PERIPHERAL__ENABLE       {1}                     \
        CONFIG.PSU__TTC0__WAVEOUT__ENABLE          {1}                     \
        CONFIG.PSU__TTC0__WAVEOUT__IO              {EMIO}                  \
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
        CONFIG.PSU__USE__M_AXI_GP0                 {0}                     \
        CONFIG.PSU__USE__M_AXI_GP1                 {0}                     \
        CONFIG.PSU__USE__M_AXI_GP2                 {1}                     \
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
    ]
    # dp=1: live video from the PL into the DisplayPort controller. The video
    # clock comes from the PS (VPLL, dp_video_ref_clk) and is looped back as
    # dp_video_in_clk; 74.25 MHz = 1280x720 at 60 Hz.
    if {$opt(dp)} {
        lappend cfg CONFIG.PSU__USE__VIDEO {1} \
                    CONFIG.PSU__CRF_APB__DP_VIDEO_REF_CTRL__FREQMHZ {74.25}
    }
    return $cfg
}
