`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// c_tero_loop.v  --  Configurable TERO built from the C-RO of Peetermans et al.
//                    (FPL 2019), paper Fig. 4.  Used for the Fig. 7 comparison.
//
// Four copies of every element. Buffer stages are 4:1 muxes (LUT6) that pick
// one of the four copies of the previous stage with 2 parameter bits.
// NAND copy k takes its input from copy k of the previous stage, so the
// selection bits of the stage *after* a NAND decide which NAND copy (and
// therefore which copy of the stage before it) is in the loop.
// 8 buffer stages x 2 bits = 16-bit parameter; 32 + 8 + 1 = 41 LUTs.
//
// Stage order: 0=NAND1, 1..3 = buffers, 4=NAND2, 5..9 = buffers.
// Buffer stage j uses param bits [2b+1:2b] with b = 0,1,2 (j=1..3), 3..7 (j=5..9)
//-----------------------------------------------------------------------------
(* DONT_TOUCH = "true", KEEP_HIERARCHY = "true" *)
module c_tero_loop (
    input  wire        ctrl,
    input  wire [15:0] param,
    output wire        tero_out
);
    localparam integer NS = 10;
    localparam [63:0] INIT_MUX4 = 64'hFF00F0F0CCCCAAAA; // out = I[{I5,I4}] of I0..I3

    (* DONT_TOUCH = "true" *) wire [4*NS-1:0] c;   // c[4*stage + copy]

    genvar j, k;
    generate
        for (j = 0; j < NS; j = j + 1) begin : g_stage
            localparam integer P   = (j == 0) ? NS - 1 : j - 1;
            localparam         ISN = (j == 0) || (j == 4);
            localparam integer B   = (j < 4) ? (j - 1) : (j - 2);  // buffer index
            for (k = 0; k < 4; k = k + 1) begin : g_copy
                if (ISN) begin : g_nand
                    (* DONT_TOUCH = "true" *)
                    LUT2 #(.INIT(4'h7)) u_nand (
                        .O(c[4*j+k]), .I0(c[4*P+k]), .I1(ctrl));
                end else begin : g_buf
                    (* DONT_TOUCH = "true" *)
                    LUT6 #(.INIT(INIT_MUX4)) u_mux (
                        .O(c[4*j+k]),
                        .I0(c[4*P+0]), .I1(c[4*P+1]), .I2(c[4*P+2]), .I3(c[4*P+3]),
                        .I4(param[2*B]), .I5(param[2*B+1]));
                end
            end
        end
    endgenerate

    // TO = copy of stage 9 that feeds the NAND1 copy chosen by stage 1 (bits 1:0)
    (* DONT_TOUCH = "true" *)
    LUT6 #(.INIT(INIT_MUX4)) u_out (
        .O(tero_out),
        .I0(c[4*(NS-1)+0]), .I1(c[4*(NS-1)+1]), .I2(c[4*(NS-1)+2]), .I3(c[4*(NS-1)+3]),
        .I4(param[0]), .I5(param[1]));
endmodule
