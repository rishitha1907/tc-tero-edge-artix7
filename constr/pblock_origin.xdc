## ===========================================================================
## pblock_origin.xdc -- places the TERO ring at a fixed "origin", like the
## paper's RLOC_ORIGIN experiments (X4Y16, X4Y32, ..., X8Y80).
## To change the origin, edit the two coordinates in resize_pblock below:
##   SLICE_X<X>Y<Y>:SLICE_X<X+3>Y<Y+4>
## ===========================================================================
create_pblock pblock_ring
add_cells_to_pblock [get_pblocks pblock_ring] [get_cells u_rng/u_loop]
resize_pblock [get_pblocks pblock_ring] -add {SLICE_X4Y16:SLICE_X7Y20}
set_property IS_SOFT FALSE [get_pblocks pblock_ring]
