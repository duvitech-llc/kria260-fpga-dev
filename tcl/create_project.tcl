# ============================================================
# KV260 Vivado Project Creation Script
# Target: XCK26-SFVC784-2LV-C (Kria K26 SoM)
# Board:  Kria KV260 Vision AI Starter Kit
# ============================================================

# ---- User-configurable ----
set proj_name "kv260_base"
set script_dir [file dirname [file normalize [info script]]]
set proj_dir  [file normalize [file join $script_dir ".." "vivado"]]
set part      "xck26-sfvc784-2LV-c"

# ---- Create project ----
create_project $proj_name $proj_dir -part $part -force

# Leave board_part empty to maximize portability (board files optional).
# If the XilinxBoardStore is on your board_repo path you can uncomment:
#   set_property board_part xilinx.com:kv260_starter_kit:part0:1.4 [current_project]
set_property board_part "" [current_project]
set_property target_language Verilog [current_project]
set_property default_lib xil_defaultlib [current_project]

# ---- Add RTL sources ----
add_files -norecurse [file normalize [file join $script_dir ".." "src" "rtl"]]

# ---- Add constraints ----
add_files -fileset constrs_1 [file normalize [file join $script_dir ".." "xdc" "kv260_base.xdc"]]

# ---- Set top module ----
set_property top top [current_fileset]

# ---- VHDL 2008 compatibility ----
set_property enable_vhdl_2008 1 [current_project]

# ---- Create block design ----
source [file join $script_dir "create_bd.tcl"]

# ---- Ensure top-level wrapper is active ----
set_property top zynq_bd_wrapper [current_fileset]
update_compile_order -fileset sources_1

# ---- Set top module (RTL wraps BD wrapper) ----
set_property top top [current_fileset]

puts "INFO: Project $proj_name created successfully"
