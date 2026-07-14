# ============================================================
# KV260 bare-metal JTAG bring-up (xsdb)
#
# Configures the PL with the bitstream, initializes the PS
# (psu_init from the exported platform), then downloads and
# runs the bare-metal ELF on A53 core 0.
#
# Run from the sw/ directory with the board powered and the
# USB JTAG/UART cable (J4) connected:
#   xsdb run_jtag.tcl
#
# Workspace location must match create_vitis.py (default
# C:\kv260_ws on Windows, sw/workspace elsewhere; override
# with the VITIS_WORKSPACE environment variable).
#
# Serial console: second COM port of the FTDI, 115200 8N1.
# ============================================================

if {[info exists ::env(VITIS_WORKSPACE)]} {
    set ws $::env(VITIS_WORKSPACE)
} elseif {$::tcl_platform(platform) eq "windows"} {
    set ws "C:/kv260_ws"
} else {
    set ws "workspace"
}

set bit ../vivado/kv260_base.runs/impl_1/top.bit
set elf $ws/pmod_gpio/build/pmod_gpio.elf

# psu_init.tcl location varies between Vitis versions - search for it
set psu_init ""
foreach cand [list $ws/kv260_pfm/hw/psu_init.tcl \
                   {*}[glob -nocomplain $ws/kv260_pfm/*/psu_init.tcl] \
                   {*}[glob -nocomplain $ws/kv260_pfm/*/*/psu_init.tcl]] {
    if {[file exists $cand]} { set psu_init $cand; break }
}
if {$psu_init eq ""} {
    error "psu_init.tcl not found under $ws/kv260_pfm - build the platform first (vitis -s create_vitis.py)"
}

connect

# Stop whatever the QSPI boot firmware is doing
targets -set -nocase -filter {name =~ "*PSU*"}
stop
after 500

# Configure the PL
fpga $bit
puts "INFO: PL configured with $bit"

# PS init (clocks, DDR, MIO) from our hardware design
source $psu_init
psu_init
after 500
psu_ps_pl_isolation_removal
after 500
psu_ps_pl_reset_config
catch {psu_protection}

# Download and run on A53 #0
targets -set -nocase -filter {name =~ "*A53*#0"}
rst -processor -clear-registers
dow $elf
con

puts "INFO: pmod_gpio running - PMOD J2 walking-one, fan PWM ramping"
