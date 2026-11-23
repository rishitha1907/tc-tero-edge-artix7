`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tero_loop.v  --  Plain TERO (paper Fig. 2, Section III), used for Table I.
// NAND = LUT2, buffer = LUT1, all DONT_TOUCH. N = 3, M = 5.
// Stage order: 0=NAND1, 1..3 buffers, 4=NAND2, 5..9 buffers.
//-----------------------------------------------------------------------------
(* DONT_TOUCH = "true", KEEP_HIERARCHY = "true" *)
module tero_loop (
    input  wire ctrl,
    output wire tero_out
);
    localparam integer NS = 10;
    (* DONT_TOUCH = "true" *) wire [NS-1:0] n;

    genvar j;
    generate
        for (j = 0; j < NS; j = j + 1) begin : g_stage
            localparam integer P = (j == 0) ? NS - 1 : j - 1;
            if ((j == 0) || (j == 4)) begin : g_nand
                (* DONT_TOUCH = "true" *)
                LUT2 #(.INIT(4'h7)) u_nand (.O(n[j]), .I0(n[P]), .I1(ctrl));
            end else begin : g_buf
                (* DONT_TOUCH = "true" *)
                LUT1 #(.INIT(2'b10)) u_buf (.O(n[j]), .I0(n[P]));
            end
        end
    endgenerate

    assign tero_out = n[NS-1];
endmodule
