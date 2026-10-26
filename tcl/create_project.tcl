# ============================================================
# KV260 Vivado project creation
# Target: XCK26-SFVC784-2LV-C (K26 SoM on the KV260 carrier)
#
#   vivado -mode batch -source tcl/create_project.tcl
#   vivado -mode batch -source tcl/create_project.tcl -tclargs pmod=0
#
# Options are described in tcl/common.tcl. Re-running recreates vivado/.
# ============================================================

source [file join [file dirname [file normalize [info script]]] "common.tcl"]
source [file join $script_dir "ps_config.tcl"]
parse_options
puts "INFO: options: [options_string]"

# ---- Create project ----
# Works whether or not a project is already open in this Vivado session.
if {[llength [get_projects -quiet]] > 0} { close_project }
create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog        [current_project]
set_property default_lib     xil_defaultlib [current_project]

# ---- RTL sources ----
add_files -norecurse [file join $repo_dir src rtl top.v]
add_files -norecurse [glob [file join $repo_dir src rtl common *.v]]
add_files -norecurse [glob [file join $repo_dir src rtl video *.v]]

# ---- Constraints: one file per option, loaded only when its ports exist ----
add_files -fileset constrs_1 -norecurse [file join $repo_dir xdc kv260_base.xdc]
if {$opt(pmod)} {
    add_files -fileset constrs_1 -norecurse [file join $repo_dir xdc kv260_pmod.xdc]
}
if {$opt(dp)} {
    # Refers to the PS's pins and clocks, which exist only once the
    # out-of-context PS is linked in: implementation only.
    set f [add_files -fileset constrs_1 -norecurse [file join $repo_dir xdc kv260_dp.xdc]]
    set_property USED_IN_SYNTHESIS false [get_files $f]
}
if {$opt(iic)} {
    add_files -fileset constrs_1 -norecurse [file join $repo_dir xdc kv260_cam_ctrl.xdc]
}
if {$opt(cam) ne "none"} {
    add_files -fileset constrs_1 -norecurse [file join $repo_dir xdc kv260_cam_$opt(cam).xdc]
}

# ---- Build options seen by top.v ----
set defines {}
if {$opt(pmod)} { lappend defines USE_PMOD }
if {$opt(fan) eq "rtl"} { lappend defines USE_FAN_RTL }
if {$opt(dp)}           { lappend defines USE_DP }
if {$opt(iic)}          { lappend defines USE_IIC }
if {$opt(cpu) eq "mbv"} { lappend defines USE_MBV }
if {$opt(cam) ne "none"} {
    lappend defines USE_CAM
    lappend defines CAM_LANES=[expr {$opt(cam) eq "rpi" ? 2 : 4}]
}
set_property verilog_define $defines [get_filesets sources_1]
set_property verilog_define $defines [get_filesets sim_1]

# ---- Block design (always: the PS clocks the PL) ----
source [file join $script_dir "create_bd.tcl"]

# ---- Top module ----
set_property top top [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "INFO: Project $proj_name created in $proj_dir ([options_string])"
