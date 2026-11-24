# ============================================================================
# build.tcl -- one-command build for the EDGE Artix-7 TC-TERO reproduction
#
# Run from the project root (the folder that contains rtl/ constr/ scripts/):
#   vivado -mode batch -source scripts/build.tcl -tclargs <LOOP_TYPE> <X> <Y>
#
#   LOOP_TYPE : 0 = plain TERO, 1 = C-TERO (16-bit), 2 = TC-TERO (20-bit)
#   X Y       : ring origin (lower-left slice of a 4x5-slice pblock)
#   [USE_BUFG]: optional 4th arg, 1 = use BUFG instead of BUFR (fallback only)
# Examples:
#   vivado -mode batch -source scripts/build.tcl -tclargs 2 4 16
#   vivado -mode batch -source scripts/build.tcl -tclargs 0 8 64
# Output: build/<name>/tero_<name>.bit and reports in the same folder
# ============================================================================
set loop_type 2 ; set ox 4 ; set oy 16 ; set use_bufg 0
if {[llength $argv] >= 1} { set loop_type [lindex $argv 0] }
if {[llength $argv] >= 3} { set ox [lindex $argv 1] ; set oy [lindex $argv 2] }
if {[llength $argv] >= 4} { set use_bufg [lindex $argv 3] }

set names {plain c_tero tc_tero}
set name  "[lindex $names $loop_type]_X${ox}Y${oy}"
set part  xc7a35tftg256-1
set out   [file normalize "build/$name"]
file mkdir $out
puts "=== Building $name for $part -> $out"

read_verilog [glob rtl/*.v]
read_xdc constr/edge_a7_tero.xdc

synth_design -top tero_top -part $part -generic LOOP_TYPE=$loop_type -generic USE_BUFG=$use_bufg

# fixed placement origin for the ring (paper: RLOC_ORIGIN)
create_pblock pblock_ring
add_cells_to_pblock [get_pblocks pblock_ring] [get_cells u_rng/u_loop]
resize_pblock [get_pblocks pblock_ring] -add "SLICE_X${ox}Y${oy}:SLICE_X[expr {$ox+3}]Y[expr {$oy+4}]"
set_property IS_SOFT FALSE [get_pblocks pblock_ring]

# the ring is a deliberate combinational loop
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *u_rng/u_loop/*}]
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]

opt_design
place_design
route_design

report_utilization -hierarchical -file $out/util_hier.rpt
report_utilization               -file $out/util.rpt
report_timing_summary            -file $out/timing.rpt
report_drc                       -file $out/drc.rpt
write_checkpoint -force $out/routed.dcp
write_bitstream  -force $out/tero_$name.bit

# print the TRNG area (the paper's Table II counts the TRNG incl. controller)
puts "=== u_rng  LUTs: [llength [get_cells -hier -filter {PRIMITIVE_GROUP == LUT && NAME =~ u_rng/*}]]  FFs: [llength [get_cells -hier -filter {PRIMITIVE_GROUP == FLOP_LATCH && NAME =~ u_rng/*}]]"
puts "=== ring   LUTs: [llength [get_cells -hier -filter {PRIMITIVE_GROUP == LUT && NAME =~ u_rng/u_loop/*}]]  F7: [llength [get_cells -hier -filter {PRIMITIVE_GROUP == MUXFX && NAME =~ u_rng/u_loop/*}]]"
puts "=== DONE: $out/tero_$name.bit"
