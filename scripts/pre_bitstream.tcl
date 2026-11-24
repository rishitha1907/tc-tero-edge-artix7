# pre_bitstream.tcl -- the TERO ring is an intentional combinational loop.
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
catch { set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *u_rng/u_loop/*}] }
