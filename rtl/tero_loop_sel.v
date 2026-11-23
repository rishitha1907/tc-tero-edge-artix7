`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tero_loop_sel.v -- picks the ring variant at elaboration time.
//   LOOP_TYPE = 0 : plain TERO          (Table I)
//   LOOP_TYPE = 1 : C-TERO,  16-bit     (Fig. 7, left half)
//   LOOP_TYPE = 2 : TC-TERO, 20-bit     (proposed; Fig. 7 right, Fig. 8, tests)
//   LOOP_TYPE = 9 : behavioural model, simulation only (tb_top.v)
// The instance of this module is always named u_rng/u_loop, so the XDC and
// Tcl constraints (pblock, combinational-loop waiver) never change.
//-----------------------------------------------------------------------------
(* DONT_TOUCH = "true", KEEP_HIERARCHY = "true" *)
module tero_loop_sel #(
    parameter integer LOOP_TYPE = 2
)(
    input  wire        ctrl,
    input  wire [19:0] param,
    output wire        tero_out
);
    generate
        if (LOOP_TYPE == 0) begin : g_plain
            tero_loop    u_ring (.ctrl(ctrl), .tero_out(tero_out));
        end else if (LOOP_TYPE == 1) begin : g_c
            c_tero_loop  u_ring (.ctrl(ctrl), .param(param[15:0]), .tero_out(tero_out));
        end else if (LOOP_TYPE == 9) begin : g_model
            // SIMULATION ONLY: behavioural ring that makes exactly
            // 100 + param[3:0] rising edges (4 ns period) after CTRL rises.
            // synthesis translate_off
            reg r = 1'b1;
            integer k;
            always @(posedge ctrl) begin
                for (k = 0; k < 100 + param[3:0]; k = k + 1) begin
                    #2 r = 1'b0;
                    #2 r = 1'b1;
                end
            end
            assign tero_out = r;
            // synthesis translate_on
        end else begin : g_tc
            tc_tero_loop u_ring (.ctrl(ctrl), .param(param), .tero_out(tero_out));
        end
    endgenerate
endmodule
