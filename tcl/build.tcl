# ============================================================
# KV260: synthesis, implementation, bitstream
#
#   vivado -mode batch -source tcl/build.tcl
#   vivado -mode batch -source tcl/build.tcl -tclargs jobs=16
#
# Builds the project made by create_project.tcl as it is (options are chosen
# there). Results go to output/:
#   kv260_base.bit      bitstream
#   kv260_base.xsa      hardware handoff for Vitis (with the bitstream)
#   psu_init.tcl        PS initialisation for xsdb (used by tcl/program.tcl)
#   timing_summary.rpt, utilization.rpt
# Fails (non-zero exit) if a run fails or timing is not met.
# ============================================================

source [file join [file dirname [file normalize [info script]]] "common.tcl"]
parse_options

set xpr [file join $proj_dir "$proj_name.xpr"]
if {![file exists $xpr]} { error "Project not found: $xpr. Run tcl/create_project.tcl first." }
if {[llength [get_projects -quiet]] > 0} { close_project }
open_project $xpr

reset_run synth_1
launch_runs synth_1 -jobs $opt(jobs)
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed; see vivado/$proj_name.runs/synth_1/runme.log" }

launch_runs impl_1 -to_step write_bitstream -jobs $opt(jobs)
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation failed; see vivado/$proj_name.runs/impl_1/runme.log" }

# ---- Collect results ----
set out_dir [file join $repo_dir "output"]
file mkdir $out_dir
set impl_dir [get_property DIRECTORY [get_runs impl_1]]
file copy -force [file join $impl_dir "top.bit"] [file join $out_dir "$proj_name.bit"]

open_run impl_1
report_timing_summary -file [file join $out_dir "timing_summary.rpt"]
report_utilization    -file [file join $out_dir "utilization.rpt"]
write_hw_platform -fixed -include_bit -force -file [file join $out_dir "$proj_name.xsa"]

# PS initialisation script, generated with the PS IP; program.tcl sources it.
set psu [glob -nocomplain [file join $proj_dir "$proj_name.gen" sources_1 bd $bd_name ip * psu_init.tcl]]
if {[llength $psu] != 1} { error "Expected one psu_init.tcl under vivado/$proj_name.gen, found: $psu" }
file copy -force [lindex $psu 0] [file join $out_dir "psu_init.tcl"]

set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "INFO: Build complete. WNS = $wns ns, WHS = $whs ns. Bitstream: output/$proj_name.bit"
if {$wns < 0 || $whs < 0} { error "Timing not met (WNS $wns ns, WHS $whs ns); see output/timing_summary.rpt" }
