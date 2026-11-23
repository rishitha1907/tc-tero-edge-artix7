`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// uart.v -- 8N1 UART TX/RX and a simple synchronous FIFO.
// DIV = clock cycles per bit. 100 MHz / 33 = 3.03 Mbaud (+1 %), which talks
// to a PC port opened at 3,000,000 baud (same rate as the original repo).
//-----------------------------------------------------------------------------
module uart_tx #(parameter integer DIV = 33) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       valid,
    output wire       ready,
    output reg        txd = 1'b1
);
    reg [9:0] sh  = 10'h3FF;
    reg [3:0] nb  = 4'd0;
    reg [7:0] dc  = 8'd0;
    assign ready = (nb == 4'd0);
    always @(posedge clk) begin
        if (rst) begin
            nb <= 4'd0; txd <= 1'b1; dc <= 8'd0;
        end else if (nb == 4'd0) begin
            txd <= 1'b1;
            if (valid) begin
                sh <= {1'b1, data, 1'b0};   // stop, data (LSB first), start
                nb <= 4'd10; dc <= 8'd0;
            end
        end else begin
            txd <= sh[0];
            if (dc == DIV - 1) begin
                dc <= 8'd0; sh <= {1'b1, sh[9:1]}; nb <= nb - 4'd1;
            end else
                dc <= dc + 8'd1;
        end
    end
endmodule

module uart_rx #(parameter integer DIV = 33) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rxd,
    output reg  [7:0] data  = 8'd0,
    output reg        valid = 1'b0
);
    (* ASYNC_REG = "TRUE" *) reg r0 = 1'b1, r1 = 1'b1;
    reg [7:0] dc = 8'd0;
    reg [3:0] bi = 4'd0;
    reg       busy = 1'b0;
    reg [7:0] sh = 8'd0;
    always @(posedge clk) begin
        r0 <= rxd; r1 <= r0;
        valid <= 1'b0;
        if (rst) begin
            busy <= 1'b0;
        end else if (!busy) begin
            if (!r1) begin busy <= 1'b1; dc <= 8'd0; bi <= 4'd0; end
        end else begin
            if ((bi == 4'd0 && dc == (DIV/2) - 1) || (bi != 4'd0 && dc == DIV - 1)) begin
                dc <= 8'd0;
                if (bi == 4'd0) begin
                    if (r1) busy <= 1'b0;          // false start
                    else    bi <= 4'd1;
                end else if (bi <= 4'd8) begin
                    sh <= {r1, sh[7:1]}; bi <= bi + 4'd1;
                end else begin                     // stop bit
                    busy <= 1'b0;
                    if (r1) begin data <= sh; valid <= 1'b1; end
                end
            end else
                dc <= dc + 8'd1;
        end
    end
endmodule

module fifo8 #(parameter integer AW = 12) (     // 4096 bytes
    input  wire          clk,
    input  wire          rst,
    input  wire [7:0]    wdata,
    input  wire          we,
    input  wire          re,
    output wire [7:0]    rdata,
    output wire          empty,
    output reg  [AW:0]   count = 0
);
    (* ram_style = "block" *) reg [7:0] mem [0:(1<<AW)-1];
    reg [AW-1:0] wp = 0, rp = 0;
    reg [7:0]    rd = 8'd0;
    reg          rd_valid = 1'b0;
    // first-word-fall-through style using a 1-entry output register
    wire do_w = we && (count < (1 << AW));
    wire raw_empty = (count == 0);
    wire fetch = !raw_empty && (!rd_valid || re);
    assign rdata = rd;
    assign empty = !rd_valid;
    always @(posedge clk) begin
        if (do_w) mem[wp] <= wdata;
        if (fetch) rd <= mem[rp];
    end
    always @(posedge clk) begin
        if (rst) begin
            wp <= 0; rp <= 0; count <= 0; rd_valid <= 1'b0;
        end else begin
            if (do_w) wp <= wp + 1'b1;
            if (fetch) rp <= rp + 1'b1;
            count <= count + (do_w ? 1'b1 : 1'b0) - (fetch ? 1'b1 : 1'b0);
            if (fetch)   rd_valid <= 1'b1;
            else if (re) rd_valid <= 1'b0;
        end
    end
endmodule
