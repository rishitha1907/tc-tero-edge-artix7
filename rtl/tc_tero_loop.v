`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tc_tero_loop.v  --  Three-path Configurable TERO (TC-TERO), FPL 2020, Fig. 5
//
// Ring of 10 stages (two NANDs + N=3 / M=5 buffers):
//   stage 0      : NAND1   (input from stage 9)
//   stages 1..3  : branch-1 buffers  (N = 3)
//   stage 4      : NAND2   (input from stage 3)
//   stages 5..9  : branch-2 buffers  (M = 5)
//
// Every stage has two 6-input LUTs (upper u, lower l) and one F7MUX (f).
// Each LUT is a 3:1 mux of the previous stage {u, l, f}; NAND stages also
// AND with CTRL and invert (NAND + 3:1 mux packed in one LUT6, as in paper).
//
// Stage j uses parameter bits {param[2j+1], param[2j]} = {s1, s0}:
//   s1=0,s0=0 -> previous upper LUT      (direct path)
//   s1=0,s0=1 -> previous lower LUT      (direct path)
//   s1=1      -> previous F7MUX output   (3rd path; F7MUX picks u/l by s0)
// The F7MUX after stage j is steered by the even bit of stage j+1.
// => 10 stages x 2 bits = 20-bit parameter, 20 + 1 LUTs, 10 F7MUXes.
//-----------------------------------------------------------------------------
(* DONT_TOUCH = "true", KEEP_HIERARCHY = "true" *)
module tc_tero_loop (
    input  wire        ctrl,
    input  wire [19:0] param,
    output wire        tero_out
);
    localparam integer NS = 10;
    // INIT: I0=u_prev I1=l_prev I2=f_prev I3=s0 I4=s1 I5=ctrl
    localparam [63:0] INIT_BUF  = 64'hF0F0CCAAF0F0CCAA; // out = s1 ? f : (s0 ? l : u)
    localparam [63:0] INIT_NAND = 64'h0F0F3355FFFFFFFF; // out = ~(ctrl & mux)

    (* DONT_TOUCH = "true" *) wire [NS-1:0] u;
    (* DONT_TOUCH = "true" *) wire [NS-1:0] l;
    (* DONT_TOUCH = "true" *) wire [NS-1:0] f;

    genvar j;
    generate
        for (j = 0; j < NS; j = j + 1) begin : g_stage
            localparam integer P   = (j == 0)      ? NS - 1 : j - 1;  // previous stage
            localparam integer NX  = (j == NS - 1) ? 0      : j + 1;  // next stage
            localparam         ISN = (j == 0) || (j == 4);            // NAND stage?
            localparam [63:0]  INI = ISN ? INIT_NAND : INIT_BUF;
            wire c5 = ISN ? ctrl : 1'b0;

            (* DONT_TOUCH = "true" *)
            LUT6 #(.INIT(INI)) u_up (
                .O(u[j]), .I0(u[P]), .I1(l[P]), .I2(f[P]),
                .I3(param[2*j]), .I4(param[2*j+1]), .I5(c5));

            (* DONT_TOUCH = "true" *)
            LUT6 #(.INIT(INI)) u_lo (
                .O(l[j]), .I0(u[P]), .I1(l[P]), .I2(f[P]),
                .I3(param[2*j]), .I4(param[2*j+1]), .I5(c5));

            (* DONT_TOUCH = "true" *)
            MUXF7 u_f7 (.O(f[j]), .I0(u[j]), .I1(l[j]), .S(param[2*NX]));
        end
    endgenerate

    // TO = the same signal that enters NAND1 (stage-0 selection of stage 9)
    (* DONT_TOUCH = "true" *)
    LUT6 #(.INIT(INIT_BUF)) u_out (
        .O(tero_out), .I0(u[NS-1]), .I1(l[NS-1]), .I2(f[NS-1]),
        .I3(param[0]), .I4(param[1]), .I5(1'b0));
endmodule
