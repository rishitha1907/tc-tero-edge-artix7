`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// host_ctrl.v -- PC command interface (replaces the button-driven mode select
// of the original Arty design; all numbers are big-endian on the wire).
//
//  'P'                              -> "TERO", LOOP_TYPE, VERSION   (6 bytes)
//  'S' start[23:0] count[23:0]      -> parameter search: for each parameter
//        4096 trials, 8 bytes/param = {sat_any, sum[30:0], sqsum[31:0]}
//        (same record layout as the original repo's 16-hex-digit output)
//  'C' param[23:0] n[31:0]          -> counter mode: n raw counter bytes
//  'T' param[23:0] n[31:0]          -> TRNG mode: n bytes, each = 8 LSBs of
//        non-saturated counter values, first bit in the MSB
//  'C' and 'T' end with a 16-byte trailer:
//        active_cycles[63:0], trials[31:0], saturated_trials[31:0]
//  active_cycles counts 100 MHz cycles the generator was running (time spent
//  waiting for the UART is excluded) -> true on-chip throughput.
//-----------------------------------------------------------------------------
module host_ctrl #(
    parameter integer LOOP_TYPE = 2,
    parameter [7:0]   VERSION   = 8'h01
)(
    input  wire        clk,
    input  wire        rst,
    // UART rx
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    // FIFO write side
    output reg  [7:0]  f_wdata,
    output reg         f_we,
    input  wire [12:0] f_count,
    // TRNG core
    output reg  [19:0] param,
    output reg         start,
    input  wire        ready,
    input  wire        done,
    input  wire [7:0]  cnt,
    input  wire        sat,
    // status
    output wire        busy,
    output reg  [1:0]  mode
);
    localparam [7:0]  LT8 = LOOP_TYPE;
    localparam integer FIFO_LIM = 4096 - 32;   // keep room for multi-byte records
    localparam [1:0] M_NONE = 2'd0, M_S = 2'd1, M_C = 2'd2, M_T = 2'd3;

    // ---------------- command receive
    reg [7:0]  cmd = 8'd0;
    reg [3:0]  need = 4'd0;      // argument bytes still expected
    reg [55:0] args = 56'd0;
    reg        go = 1'b0;

    // ---------------- multi-byte output sequencer
    reg [127:0] ob = 128'd0;
    reg [4:0]   ob_n = 5'd0;     // bytes left in ob

    // ---------------- run state
    localparam [2:0] R_IDLE = 3'd0, R_RUN = 3'd1, R_EMIT = 3'd2,
                     R_TRAIL = 3'd3, R_FLUSH = 3'd4;
    reg [2:0]  rs = R_IDLE;
    reg [23:0] s_left = 24'd0;
    reg [12:0] trials = 13'd0;          // per-parameter trial count (search)
    reg        issued = 1'b0;           // a trial is in flight
    reg [31:0] sum = 32'd0, sqs = 32'd0;
    reg        sany = 1'b0;
    reg [31:0] n_left = 32'd0;
    reg [7:0]  bsh = 8'd0;
    reg [2:0]  bcnt = 3'd0;
    reg [63:0] act = 64'd0;
    reg [31:0] ntr = 32'd0, nsat = 32'd0;

    assign busy = (rs != R_IDLE) || (ob_n != 0);

    wire fifo_ok = (f_count < FIFO_LIM);
    wire [15:0] sq = cnt * cnt;

    always @(posedge clk) begin
        f_we  <= 1'b0;
        start <= 1'b0;
        go    <= 1'b0;
        if (rst) begin
            need <= 4'd0; rs <= R_IDLE; ob_n <= 5'd0; mode <= M_NONE;
            issued <= 1'b0; param <= 20'd0;
        end else begin
            //---------------------------------------------- command parser
            if (rx_valid && rs == R_IDLE && ob_n == 0 && !go) begin
                if (need == 4'd0) begin
                    cmd <= rx_data;
                    case (rx_data)
                        8'h50: go <= 1'b1;                 // 'P'
                        8'h53: need <= 4'd6;               // 'S'
                        8'h43, 8'h54: need <= 4'd7;        // 'C', 'T'
                        default: ;
                    endcase
                end else begin
                    args <= {args[47:0], rx_data};
                    need <= need - 4'd1;
                    if (need == 4'd1) go <= 1'b1;
                end
            end

            //---------------------------------------------- output sequencer
            if (ob_n != 0) begin
                f_wdata <= ob[127:120];
                f_we    <= 1'b1;
                ob      <= {ob[119:0], 8'h00};
                ob_n    <= ob_n - 5'd1;
            end

            //---------------------------------------------- command start
            if (go) begin
                case (cmd)
                8'h50: begin   // ping
                    ob   <= {8'h54, 8'h45, 8'h52, 8'h4F, LT8, VERSION, 80'd0};
                    ob_n <= 5'd6;
                end
                8'h53: begin   // search
                    param  <= args[43:24];
                    s_left <= args[23:0];
                    mode <= M_S; rs <= R_RUN;
                    trials <= 13'd0; sum <= 32'd0; sqs <= 32'd0; sany <= 1'b0;
                    issued <= 1'b0;
                    if (args[23:0] == 24'd0) begin rs <= R_IDLE; mode <= M_NONE; end
                end
                default: begin // 'C' or 'T'
                    param  <= args[51:32];
                    n_left <= args[31:0];
                    mode   <= (cmd == 8'h43) ? M_C : M_T;
                    rs     <= R_RUN;
                    issued <= 1'b0; bcnt <= 3'd0;
                    act <= 64'd0; ntr <= 32'd0; nsat <= 32'd0;
                    if (args[31:0] == 32'd0) rs <= R_TRAIL;
                end
                endcase
            end

            //---------------------------------------------- run
            case (rs)
            R_RUN: begin
                if (mode == M_S) begin
                    if (!issued && ready && trials != 13'd4096) begin
                        start <= 1'b1; issued <= 1'b1;
                    end
                    if (done) begin
                        issued <= 1'b0;
                        sum  <= sum + cnt;
                        sqs  <= sqs + sq;
                        sany <= sany | sat;
                        trials <= trials + 13'd1;
                    end
                    if (trials == 13'd4096 && !issued) rs <= R_EMIT;
                end else begin
                    // C / T : count active cycles unless stalled by the FIFO
                    if (!(ready && !issued && !fifo_ok)) act <= act + 64'd1;
                    if (!issued && ready && fifo_ok && n_left != 0) begin
                        start <= 1'b1; issued <= 1'b1;
                    end
                    if (done) begin
                        issued <= 1'b0;
                        ntr <= ntr + 32'd1;
                        if (sat) nsat <= nsat + 32'd1;
                        if (mode == M_C) begin
                            f_wdata <= cnt; f_we <= 1'b1;
                            n_left  <= n_left - 32'd1;
                            if (n_left == 32'd1) rs <= R_TRAIL;
                        end else if (!sat) begin
                            bsh  <= {bsh[6:0], cnt[0]};
                            bcnt <= bcnt + 3'd1;
                            if (bcnt == 3'd7) begin
                                f_wdata <= {bsh[6:0], cnt[0]}; f_we <= 1'b1;
                                n_left  <= n_left - 32'd1;
                                if (n_left == 32'd1) rs <= R_TRAIL;
                            end
                        end
                    end
                end
            end
            R_EMIT: begin   // one search record
                if (fifo_ok && ob_n == 0) begin
                    ob   <= {sany, sum[30:0], sqs, 64'd0};
                    ob_n <= 5'd8;
                    trials <= 13'd0; sum <= 32'd0; sqs <= 32'd0; sany <= 1'b0;
                    if (s_left == 24'd1) begin
                        rs <= R_FLUSH;
                    end else begin
                        s_left <= s_left - 24'd1;
                        param  <= param + 20'd1;
                        rs     <= R_RUN;
                    end
                end
            end
            R_TRAIL: begin
                if (fifo_ok && ob_n == 0) begin
                    ob   <= {act, ntr, nsat};
                    ob_n <= 5'd16;
                    rs   <= R_FLUSH;
                end
            end
            R_FLUSH: begin
                if (ob_n == 0) begin rs <= R_IDLE; mode <= M_NONE; end
            end
            default: ;
            endcase
        end
    end
endmodule
