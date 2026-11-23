`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tero_rng.v -- TERO ring + controller, paper Section III / Fig. 3.
//
// One "trial":
//   1. CTRL=0, counter cleared, end-detector preset   (ring held: all nodes 1)
//   2. CTRL=1 -> ring oscillates a random number of times, then settles
//   3. TO (ring output) clocks a 9-bit counter through a BUFR.
//      Counter saturates when Q[8]=1  -> reported as 0xFF.
//   4. End detection: a D-FF clocked by TO is precharged (async PRE) to 1 at
//      the start of every 40 ns window (4 cycles @ 100 MHz); any TO rising
//      edge clears it to Q[8]. If it is still 1 at the end of the window,
//      the oscillation has ended (or the counter saturated).
//   5. Fail-safe timeout of 2 us (200 cycles) -> result forced to 0xFF.
// clk must be 100 MHz so that the 40 ns / 2 us values match the paper.
//-----------------------------------------------------------------------------
module tero_rng #(
    parameter integer LOOP_TYPE   = 2,
    parameter integer USE_BUFG    = 0,     // 0: BUFR as in the paper, 1: BUFG fallback
    parameter integer RST_CYC     = 2,     // extra cycles CTRL low before a trial
    parameter integer TIMEOUT_CYC = 200    // 2 us @ 100 MHz
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [19:0] param,
    input  wire        start,     // 1-cycle request, honoured when ready=1
    output wire        ready,
    output reg         done,      // 1-cycle pulse, results valid
    output reg  [7:0]  cnt,       // number of oscillations (0xFF = saturated)
    output reg         sat,       // cnt == 0xFF (saturated, 255, or timeout)
    output reg         tmo        // trial ended by timeout
);
    //------------------------------------------------------------ ring
    reg  ctrl_r = 1'b0;
    reg  clr_r  = 1'b1;
    reg  pre_r  = 1'b1;
    wire tero_out;

    tero_loop_sel #(.LOOP_TYPE(LOOP_TYPE)) u_loop (
        .ctrl(ctrl_r), .param(param), .tero_out(tero_out));

    //------------------------------------------------------------ TO clock
    wire tclk;
    generate
        if (USE_BUFG) begin : g_bufg
            BUFG u_bufr (.O(tclk), .I(tero_out));
        end else begin : g_bufr
            BUFR #(.BUFR_DIVIDE("BYPASS"), .SIM_DEVICE("7SERIES")) u_bufr (
                .O(tclk), .I(tero_out), .CE(1'b1), .CLR(1'b0));
        end
    endgenerate

    //------------------------------------------------------------ TO domain
    (* DONT_TOUCH = "true" *) reg [8:0] q = 9'd0;
    always @(posedge tclk or posedge clr_r) begin
        if (clr_r)      q <= 9'd0;
        else if (!q[8]) q <= q + 9'd1;
    end

    (* DONT_TOUCH = "true" *) reg endff = 1'b1;
    always @(posedge tclk or posedge pre_r) begin
        if (pre_r) endff <= 1'b1;
        else       endff <= q[8];
    end

    //------------------------------------------------------------ sys domain
    localparam [2:0] S_IDLE = 3'd0, S_RST = 3'd1, S_ARM = 3'd2,
                     S_RUN  = 3'd3, S_WAIT = 3'd4, S_CAP = 3'd5;
    reg [2:0] st  = S_IDLE;
    reg [7:0] tmr = 8'd0;
    reg [1:0] w   = 2'd0;
    reg       tmo_r = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg oe_cap = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg oe_s   = 1'b0;
    reg [8:0] q_cap = 9'd0;

    assign ready = (st == S_IDLE) && !rst;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            st <= S_IDLE; ctrl_r <= 1'b0; clr_r <= 1'b1; pre_r <= 1'b1;
            tmr <= 8'd0; w <= 2'd0; tmo_r <= 1'b0; oe_cap <= 1'b0; oe_s <= 1'b0;
            cnt <= 8'd0; sat <= 1'b0; tmo <= 1'b0;
        end else begin
            case (st)
            S_IDLE: begin
                ctrl_r <= 1'b0; clr_r <= 1'b1; pre_r <= 1'b1; tmo_r <= 1'b0;
                if (start) begin st <= S_RST; tmr <= 8'd0; end
            end
            S_RST: begin                       // CTRL low, counter in reset
                tmr <= tmr + 8'd1;
                if (tmr == RST_CYC - 1) begin clr_r <= 1'b0; st <= S_ARM; end
            end
            S_ARM: begin                       // release ring
                ctrl_r <= 1'b1; pre_r <= 1'b1; w <= 2'd0; tmr <= 8'd0;
                oe_cap <= 1'b0; oe_s <= 1'b0;
                st <= S_RUN;
            end
            S_RUN: begin
                w     <= w + 2'd1;
                tmr   <= tmr + 8'd1;
                pre_r <= (w == 2'd3);            // PRE high during cycle w==0
                if (w == 2'd3) oe_cap <= endff;  // sample at end of 40 ns window
                oe_s  <= oe_cap;
                if (oe_s) begin
                    st <= S_WAIT; tmr <= 8'd0; pre_r <= 1'b0;
                end else if (tmr == TIMEOUT_CYC - 1) begin
                    tmo_r <= 1'b1; st <= S_WAIT; tmr <= 8'd0; pre_r <= 1'b0;
                end
            end
            S_WAIT: begin                      // let the counter settle
                tmr <= tmr + 8'd1;
                if (tmr == 8'd1) begin q_cap <= q; st <= S_CAP; end
            end
            S_CAP: begin
                cnt  <= (tmo_r || q_cap[8]) ? 8'hFF : q_cap[7:0];
                sat  <= tmo_r || q_cap[8] || (q_cap[7:0] == 8'hFF);
                tmo  <= tmo_r;
                done <= 1'b1;
                ctrl_r <= 1'b0; clr_r <= 1'b1; pre_r <= 1'b1;
                st   <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
