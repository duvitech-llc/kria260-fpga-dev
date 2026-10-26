# ============================================================
# KV260: load the design over JTAG with xsdb (volatile; lost at power-off).
# Board powered, USB cable on J4.
#
#   xsdb tcl/program.tcl                       PL + PS initialisation only
#   xsdb tcl/program.tcl <a53 program.elf>     ... and run a program on A53 #0
# (elf=<path> also works; note that xsdb.bat splits arguments at '=', so it
# reaches this script as the two words "elf" and "<path>".)
#
# Steps: restart the PS in JTAG boot mode, load output/kv260_base.bit
# into the PL, run psu_init (clocks, DDR, MIO; output/psu_init.tcl from
# tcl/build.tcl), remove the PS-PL isolation so pl_clk0 and the AXI ports
# work, then optionally download and start an A53 program.
#
# This is an xsdb script, not a Vivado one: the KV260 PL has no clock of its
# own, so loading only the bitstream (Vivado hardware manager) is not enough.
# xsdb is in <Vitis>/bin (xsdb.bat on Windows).
# ============================================================

set repo_dir [file normalize [file join [file dirname [file normalize [info script]]] ".."]]
set out_dir  [file join $repo_dir output]
set bit      [file join $out_dir kv260_base.bit]
set psu      [file join $out_dir psu_init.tcl]

set elf ""
if {[info exists argv]} {
    foreach arg $argv {
        if {$arg eq "elf"} { continue }
        regexp {^elf=(.+)$} $arg -> arg
        if {$elf ne ""} { error "Only one ELF can be given (got '$elf' and '$arg')" }
        set elf [file normalize $arg]
    }
}
foreach f [list $bit $psu] {
    if {![file exists $f]} { error "Not found: $f. Run tcl/build.tcl first." }
}
if {$elf ne "" && ![file exists $elf]} { error "ELF not found: $elf" }

connect

# A PL access that never completed (a slave held in reset, for example)
# leaves the debug port in "AXI AP transaction error" and the PSU target
# disappears from the list. A JTAG power-on reset of the PS clears it.
if {[catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} {
    puts "INFO: PS debug target missing ([string map {"\n" " "} [targets]]); power-on reset over JTAG"
    targets -set -nocase -filter {name =~ "PS TAP"}
    rst -por
    after 3000
    disconnect
    after 1000
    connect
}

# Restart the PS in JTAG boot mode, so the Kria boot firmware in the SoM QSPI
# does not run: write the boot-mode override (CRL_APB BOOT_MODE_USER, alternate
# mode 0 = JTAG) and reset the system. Merely stopping the cores leaves them
# in states the debugger cannot use ("EDITR not ready"). The override lasts
# until the next power cycle, which boots from QSPI again; the flash is
# never written.
targets -set -nocase -filter {name =~ "*PSU*"}
mwr 0xff5e0200 0x0100
rst -system
after 2000

targets -set -nocase -filter {name =~ "*PSU*"}
fpga -file $bit
puts "INFO: PL configured with $bit"

source $psu
targets -set -nocase -filter {name =~ "*PSU*"}
psu_init
after 500
psu_ps_pl_isolation_removal
after 500
psu_ps_pl_reset_config
catch {psu_protection}
puts "INFO: PS initialised, PL clocks running"

if {$elf ne ""} {
    targets -set -nocase -filter {name =~ "*A53*#0"}
    rst -processor -clear-registers
    dow $elf
    con
    puts "INFO: Running $elf on A53 #0 (console: PS UART1, 115200 8N1; the second FTDI port, COM10 on the development PC)"
}
