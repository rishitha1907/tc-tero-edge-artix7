# ============================================================================
# create_project.tcl -- builds a normal Vivado (GUI) project for the TC-TERO
# reproduction on the EDGE Artix-7. In the Vivado Tcl Console:
#     cd C:/tc_tero_edge          (the folder that holds rtl/ constr/ scripts/)
#     source scripts/create_project.tcl
# ============================================================================
set root [pwd]
create_project tc_tero_edge $root/vivado_proj -part xc7a35tftg256-1 -force
set_property target_language Verilog [current_project]

add_files -norecurse [glob $root/rtl/*.v]
add_files -fileset constrs_1 -norecurse $root/constr/edge_a7_tero.xdc
add_files -fileset constrs_1 -norecurse $root/constr/pblock_origin.xdc
set_property used_in_synthesis false [get_files pblock_origin.xdc]

set_property top tero_top [current_fileset]
set_property generic {LOOP_TYPE=2} [current_fileset]
update_compile_order -fileset sources_1

# make sure the combinational-loop DRC is a warning when writing the bitstream
set pre [file normalize $root/scripts/pre_bitstream.tcl]
set_property STEPS.WRITE_BITSTREAM.TCL.PRE $pre [get_runs impl_1]
puts "Project created. Flow Navigator -> Generate Bitstream."
