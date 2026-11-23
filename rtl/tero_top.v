`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tero_top.v -- top level for the EDGE Artix-7 (XC7A35T-1FTG256C) board.
//
//  clk50     N11   50 MHz oscillator -> MMCM -> 100 MHz (same as Arty)
//  btn_rst   M14   centre push button SW22 (active high) = reset/abort
//  uart_txd  C4    FPGA -> PC   (FT2232H, USB port U9)
//  uart_rxd  D4    PC -> FPGA
//  led[15:0]       status (see README)
//-----------------------------------------------------------------------------
module tero_top #(
    parameter integer LOOP_TYPE = 2,     // 0 plain TERO, 1 C-TERO, 2 TC-TERO
    parameter integer USE_BUFG  = 0      // 1 only if the BUFR cannot be placed
)(
    input  wire        clk50,
    input  wire        btn_rst,
    output wire        uart_txd,
    input  wire        uart_rxd,
    output wire [15:0] led
);
    //---------------------------------------------------------- clocking
    wire clkfb, clk100_u, clk100, locked;
    MMCME2_BASE #(
        .CLKIN1_PERIOD   (20.000),
        .CLKFBOUT_MULT_F (20.000),     // VCO = 1000 MHz
        .DIVCLK_DIVIDE   (1),
        .CLKOUT0_DIVIDE_F(10.000)      // 100 MHz
    ) u_mmcm (
        .CLKIN1(clk50), .CLKFBIN(clkfb), .CLKFBOUT(clkfb),
        .CLKOUT0(clk100_u), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB(),
        .LOCKED(locked), .PWRDWN(1'b0), .RST(1'b0));
    BUFG u_bufg (.I(clk100_u), .O(clk100));

    //---------------------------------------------------------- reset
    (* ASYNC_REG = "TRUE" *) reg b0 = 1'b0, b1 = 1'b0;
    reg [3:0] rst_sr = 4'hF;
    always @(posedge clk100) begin
        b0 <= btn_rst; b1 <= b0;
        rst_sr <= {rst_sr[2:0], (b1 | ~locked)};
    end
    wire rst = |rst_sr;

    //---------------------------------------------------------- TRNG core
    wire [19:0] param;
    wire        start, ready, done, sat, tmo;
    wire [7:0]  cnt;
    tero_rng #(.LOOP_TYPE(LOOP_TYPE), .USE_BUFG(USE_BUFG)) u_rng (
        .clk(clk100), .rst(rst), .param(param), .start(start),
        .ready(ready), .done(done), .cnt(cnt), .sat(sat), .tmo(tmo));

    //---------------------------------------------------------- UART + FIFO
    wire [7:0] rx_data;  wire rx_valid;
    uart_rx #(.DIV(33)) u_rx (.clk(clk100), .rst(rst), .rxd(uart_rxd),
                              .data(rx_data), .valid(rx_valid));

    wire [7:0]  f_wdata, f_rdata;
    wire        f_we, f_empty, tx_ready;
    wire [12:0] f_count;
    wire        f_re = !f_empty && tx_ready;
    fifo8 #(.AW(12)) u_fifo (.clk(clk100), .rst(rst), .wdata(f_wdata), .we(f_we),
                             .re(f_re), .rdata(f_rdata), .empty(f_empty), .count(f_count));
    uart_tx #(.DIV(33)) u_tx (.clk(clk100), .rst(rst), .data(f_rdata), .valid(f_re),
                              .ready(tx_ready), .txd(uart_txd));

    //---------------------------------------------------------- host
    wire       busy;
    wire [1:0] mode;
    host_ctrl #(.LOOP_TYPE(LOOP_TYPE)) u_host (
        .clk(clk100), .rst(rst), .rx_data(rx_data), .rx_valid(rx_valid),
        .f_wdata(f_wdata), .f_we(f_we), .f_count(f_count),
        .param(param), .start(start), .ready(ready), .done(done),
        .cnt(cnt), .sat(sat), .busy(busy), .mode(mode));

    //---------------------------------------------------------- LEDs
    reg [26:0] hb = 27'd0;
    reg [7:0]  last_cnt = 8'd0;
    reg [22:0] rx_led = 23'd0, tx_led = 23'd0;
    always @(posedge clk100) begin
        hb <= hb + 27'd1;
        if (done) last_cnt <= cnt;
        rx_led <= rx_valid ? 23'h7FFFFF : (rx_led != 0 ? rx_led - 23'd1 : 23'd0);
        tx_led <= f_re     ? 23'h7FFFFF : (tx_led != 0 ? tx_led - 23'd1 : 23'd0);
    end
    assign led[0]    = hb[26];                 // heartbeat (~0.75 Hz): design alive
    assign led[1]    = locked;                 // MMCM locked (100 MHz OK)
    assign led[2]    = busy;                   // a command is running
    assign led[3]    = (mode == 2'd1);         // search mode
    assign led[4]    = (mode == 2'd2);         // counter mode
    assign led[5]    = (mode == 2'd3);         // TRNG mode
    assign led[6]    = (rx_led != 0);          // PC -> FPGA activity
    assign led[7]    = (tx_led != 0);          // FPGA -> PC activity
    assign led[15:8] = last_cnt;               // last oscillation count (binary)
endmodule
