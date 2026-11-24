`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_top.v -- self-checking simulation of the whole design (UART protocol,
// controller, FIFO) with the behavioural ring (LOOP_TYPE = 9).
// Expected console output ends with "ALL TESTS PASSED".
// Run time: Vivado sim, "run all" (about 3 ms of simulated time).
//-----------------------------------------------------------------------------
module tb_top;
    reg clk50 = 1'b0;
    always #10 clk50 = ~clk50;            // 50 MHz like the board

    reg  btn = 1'b0, rxd = 1'b1;
    wire txd;
    wire [15:0] led;
    tero_top #(.LOOP_TYPE(9)) dut (.clk50(clk50), .btn_rst(btn),
        .uart_txd(txd), .uart_rxd(rxd), .led(led));

    localparam real BIT = 1.0e9 / 3.0e6;  // PC side: 3,000,000 baud
    integer errors = 0;

    task send(input [7:0] b);
        integer i;
        begin
            rxd = 1'b0; #(BIT);
            for (i = 0; i < 8; i = i + 1) begin rxd = b[i]; #(BIT); end
            rxd = 1'b1; #(BIT);
        end
    endtask

    // background UART receiver
    reg [7:0] rxbuf [0:1023];
    integer   rxn = 0;
    initial begin : rxloop
        integer i; reg [7:0] b;
        forever begin
            @(negedge txd);
            #(BIT * 1.5);
            for (i = 0; i < 8; i = i + 1) begin b[i] = txd; #(BIT); end
            rxbuf[rxn] = b; rxn = rxn + 1;
        end
    end

    task expect_byte(input integer idx, input [7:0] v);
        begin
            if (rxbuf[idx] !== v) begin
                $display("  MISMATCH byte %0d: got %02h expected %02h", idx, rxbuf[idx], v);
                errors = errors + 1;
            end
        end
    endtask

    integer i, base;
    initial begin
        wait (led[1] === 1'b1);           // MMCM locked
        #2000;

        // ---- ping
        $display("[%0t] ping", $time);
        send("P");
        wait (rxn == 6);
        expect_byte(0, "T"); expect_byte(1, "E"); expect_byte(2, "R"); expect_byte(3, "O");
        expect_byte(4, 8'd9);

        // ---- counter mode, param 5 -> every value must be 105
        $display("[%0t] counter mode", $time);
        base = rxn;
        send("C"); send(8'h00); send(8'h00); send(8'h05);
        send(8'h00); send(8'h00); send(8'h00); send(8'h04);
        wait (rxn == base + 4 + 16);
        for (i = 0; i < 4; i = i + 1) expect_byte(base + i, 8'd105);
        $display("  trailer trials=%0d sat=%0d",
                 {rxbuf[base+12], rxbuf[base+13], rxbuf[base+14], rxbuf[base+15]},
                 {rxbuf[base+16], rxbuf[base+17], rxbuf[base+18], rxbuf[base+19]});
        expect_byte(base + 15, 8'd4);   // 4 trials
        expect_byte(base + 19, 8'd0);   // 0 saturated

        // ---- TRNG mode, param 3 -> 103 is odd -> LSB 1 -> bytes 0xFF
        $display("[%0t] TRNG mode", $time);
        base = rxn;
        send("T"); send(8'h00); send(8'h00); send(8'h03);
        send(8'h00); send(8'h00); send(8'h00); send(8'h02);
        wait (rxn == base + 2 + 16);
        expect_byte(base + 0, 8'hFF); expect_byte(base + 1, 8'hFF);
        expect_byte(base + 2 + 11, 8'd16);  // 16 trials for 2 bytes

        // ---- search mode, start 7, count 1 -> 4096 x 107
        $display("[%0t] search mode (4096 trials)", $time);
        base = rxn;
        send("S"); send(8'h00); send(8'h00); send(8'h07);
        send(8'h00); send(8'h00); send(8'h01);
        wait (rxn == base + 8);
        // sum = 438272 = 0x0006B000, sqsum = 46895104 = 0x02CB9000
        expect_byte(base+0, 8'h00); expect_byte(base+1, 8'h06);
        expect_byte(base+2, 8'hB0); expect_byte(base+3, 8'h00);
        expect_byte(base+4, 8'h02); expect_byte(base+5, 8'hCB);
        expect_byte(base+6, 8'h90); expect_byte(base+7, 8'h00);

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d ERRORS", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("TIMEOUT - design did not answer");
        $finish;
    end
endmodule
