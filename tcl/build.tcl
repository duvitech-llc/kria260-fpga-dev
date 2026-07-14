# Resolve paths relative to this script so it works from any cwd
set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file normalize [file join $script_dir ".." "vivado"]]

open_project [file join $proj_dir "kv260_base.xpr"]

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "ERROR: impl_1 did not complete: [get_property STATUS [get_runs impl_1]]"
}

# Export hardware (XSA with bitstream) for the Vitis bare-metal flow
write_hw_platform -fixed -include_bit -force [file join $proj_dir "kv260_base.xsa"]

puts "INFO: Build complete"
puts "INFO: Bitstream : [file join $proj_dir kv260_base.runs impl_1 top.bit]"
puts "INFO: XSA       : [file join $proj_dir kv260_base.xsa]"
