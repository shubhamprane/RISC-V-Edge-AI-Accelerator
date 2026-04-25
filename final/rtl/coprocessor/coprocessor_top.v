`timescale 1ns / 1ps

module coprocessor_top #(
    parameter ROWS = 8,
    parameter COLS = 8
)(
    input  wire clk,
    input  wire rst,
    input  wire [23:0] cop_addr,
    input  wire [31:0] cop_wdata,
    input  wire        cop_we,
    input  wire        cop_re,
    input  wire        uart_ready,
    
    input  wire        in_wclk,   // 100 MHz clock for UART BRAM writes
    input  wire        in_we,
    input  wire [7:0]  in_waddr,
    input  wire [31:0] in_wdata,

    output reg  [31:0] cop_rdata,
    output wire        cop_busy,
    output reg         cop_done,
    output reg         valid_result,
    output reg  [3:0]  class_index,
    output reg  signed [31:0] max_score
);

    // ---- Layer configuration registers ----
    reg [31:0] l1_rows, l1_cols, l2_rows, l2_cols;
    reg [31:0] l1_wt_base, l2_wt_base;
    reg [31:0] l1_bias_base, l2_bias_base;
    reg [31:0] hw_cycles_res, sw_cycles_res;
    reg [4:0]  inter_shift;
    reg        start_reg;
    reg        is_cpu_trigger;

    // ---- Active layer working registers ----
    reg [31:0] cur_rows, cur_cols, cur_wt_base, cur_bias_base;
    reg        cur_relu_en;
    reg        layer_num;  // 0 = Layer 1, 1 = Layer 2

    // ---- BRAM interface signals ----
    wire [31:0] in_rdata, wt_rdata, bias_rdata;
    reg [7:0] in_raddr, bias_raddr;
    reg [14:0] wt_raddr;
    reg [7:0] out_waddr;
    reg [31:0] out_wdata;
    reg out_we;

    // ---- Coprocessor write-back to input BRAM ----
    reg        in_rwe;
    reg [7:0]  in_rwaddr;
    reg [31:0] in_rwdata;
    
    wire [7:0] in_b_addr = in_rwe ? in_rwaddr : in_raddr;

    input_bram  u_in_bram  (.wclk(in_wclk), .we(in_we), .waddr(in_waddr), .wdata(in_wdata),
                             .rclk(clk), .re(1'b1), .rwe(in_rwe), .raddr(in_b_addr), .rdata(in_rdata),
                             .rwdata(in_rwdata));
    weight_bram u_wt_bram  (.clk(clk), .we(1'b0), .waddr(wt_raddr), .wdata(32'd0), .re(1'b1), .raddr(wt_raddr), .rdata(wt_rdata));
    bias_bram   u_bias_bram(.clk(clk), .we(1'b0), .waddr(bias_raddr), .wdata(32'd0), .re(1'b1), .raddr(bias_raddr), .rdata(bias_rdata));
    
    wire [31:0] out_rdata;
    reg [7:0] out_raddr;
    output_bram u_out_bram (.clk(clk), .we(out_we), .waddr(out_waddr), .wdata(out_wdata), .re(1'b1), .raddr(out_raddr), .rdata(out_rdata));

    // ---- Systolic array ----
    reg        systolic_flush;
    reg        systolic_a_valid;
    reg [8*COLS-1:0] systolic_a_data;
    reg        systolic_w_load;
    reg [ROWS*8*COLS-1:0] systolic_w_data_packed;
    reg [ROWS*32-1:0] systolic_bias_packed;
    wire [ROWS*32-1:0] systolic_result_packed;
    wire systolic_valid_out;

    systolic_array #(ROWS, COLS) u_systolic (
        .clk(clk), .rst(rst), .flush(systolic_flush), .a_valid(systolic_a_valid), .a_data(systolic_a_data),
        .w_load(systolic_w_load), .w_data_packed(systolic_w_data_packed), .bias_packed(systolic_bias_packed), .relu_en(cur_relu_en),
        .result_row_packed(systolic_result_packed), .valid_out(systolic_valid_out)
    );

    // ---- Argmax ----
    reg        argmax_start;
    reg [10*32-1:0] argmax_scores_packed;
    wire [3:0] argmax_winner_idx;
    wire signed [31:0] argmax_winner_val;
    wire argmax_valid;

    argmax_unit #(10, 32) u_argmax (
        .clk(clk), .rst(rst), .start(argmax_start), .scores_packed(argmax_scores_packed),
        .winner_idx(argmax_winner_idx), .winner_val(argmax_winner_val), .valid(argmax_valid)
    );

    // ---- State machine ----
    localparam S_IDLE          = 4'd0,
               S_BIAS_LOAD     = 4'd1,
               S_TILE_LOAD     = 4'd2,
               S_COLLECT_WAIT  = 4'd3,
               S_COLLECT_WRITE = 4'd4,
               S_ARGMAX_PREP   = 4'd5,
               S_ARGMAX        = 4'd6,
               S_SCALE_ADDR    = 4'd7,
               S_SCALE_WAIT    = 4'd8,
               S_SCALE_PROC    = 4'd9,
               S_L2_SETUP      = 4'd10;
    reg [3:0] state;
    reg [31:0] row_tile, col_tile;
    reg [5:0] sub_cnt;

    // Intermediate scaling registers
    reg [7:0]  scale_cnt;       // which L1 output we're reading (0..l1_rows-1)
    reg [1:0]  scale_byte_idx;  // byte position in 32-bit word (0..3)
    reg [7:0]  scale_word_idx;  // word index for input_bram write
    reg [31:0] scale_word_buf;  // accumulating 4 bytes
    
    wire signed [31:0] shifted = $signed(out_rdata) >>> inter_shift;
    wire [7:0] clamped = (out_rdata[31] || shifted[31]) ? 8'd0 : (shifted > 127 ? 8'd127 : shifted[7:0]);

    // ---- MMIO register writes ----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            l1_rows      <= 32'd128;
            l1_cols       <= 32'd784;
            l1_wt_base    <= 32'd0;
            l1_bias_base  <= 32'd0;
            l2_rows       <= 32'd10;
            l2_cols       <= 32'd128;
            l2_wt_base    <= 32'd25088;
            l2_bias_base  <= 32'd128;
            inter_shift   <= 5'd11;
            hw_cycles_res <= 32'd0;
            sw_cycles_res <= 32'd0;
            start_reg     <= 1'b0;
        end else begin
            if (cop_we) begin
                case (cop_addr[11:0])
                    12'h000: begin
                        start_reg      <= cop_wdata[0];
                        if (cop_wdata[0]) is_cpu_trigger <= 1'b1; // Only SET on start, don't clear on COP_START=0
                    end
                    12'h008: l1_wt_base    <= cop_wdata;
                    12'h00C: l1_bias_base  <= cop_wdata;
                    12'h010: l1_rows       <= cop_wdata;
                    12'h014: l1_cols       <= cop_wdata;
                    12'h018: l2_wt_base    <= cop_wdata;
                    12'h01C: l2_bias_base  <= cop_wdata;
                    12'h020: l2_rows       <= cop_wdata;
                    12'h024: l2_cols       <= cop_wdata;
                    12'h028: inter_shift   <= cop_wdata[4:0];
                    12'h02C: hw_cycles_res <= cop_wdata;
                    12'h030: sw_cycles_res <= cop_wdata;
                endcase
            end else if (uart_ready && l1_rows != 0) begin
                start_reg      <= 1;
                is_cpu_trigger <= 0; // UART triggered
            end else if (state != S_IDLE) begin
                start_reg <= 0;
            end
        end
    end

    // ---- Main state machine ----
    integer r_idx, w_idx, prev_r, prev_w, next_r, next_w;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE; row_tile <= 0; col_tile <= 0; sub_cnt <= 0;
            $display("COP: RESET");
            systolic_flush <= 0; systolic_a_valid <= 0; systolic_w_load <= 0;
            argmax_start <= 0; cop_done <= 0; valid_result <= 0;
            out_we <= 0; out_waddr <= 0; out_wdata <= 0;
            max_score <= 0; class_index <= 0;
            in_raddr <= 0; wt_raddr <= 0; bias_raddr <= 0; out_raddr <= 0;
            systolic_w_data_packed <= 0; systolic_bias_packed <= 0; argmax_scores_packed <= 0;
            systolic_a_data <= 0;
            layer_num <= 0;
            cur_rows <= 0; cur_cols <= 0; cur_wt_base <= 0; cur_bias_base <= 0; cur_relu_en <= 0;
            in_rwe <= 0; in_rwaddr <= 0; in_rwdata <= 0;
            scale_cnt <= 0; scale_byte_idx <= 0; scale_word_idx <= 0; scale_word_buf <= 0;
        end else begin
            if (state != S_IDLE && state != S_COLLECT_WAIT) begin
                 // $display("COP: State=%d sub_cnt=%d row_tile=%d col_tile=%d time=%t", state, sub_cnt, row_tile, col_tile, $time);
            end
            if (state == S_IDLE && start_reg) $display("COP: START Layer 1 at time %t", $time);
            
            systolic_flush <= 0; systolic_a_valid <= 0; systolic_w_load <= 0;
            argmax_start <= 0; out_we <= 0; in_rwe <= 0;
            
            case (state)
                S_IDLE: if (start_reg) begin
                    $display("COP: Transition S_IDLE -> S_BIAS_LOAD");
                    // Start Layer 1
                    layer_num    <= 0;
                    cur_rows     <= l1_rows;
                    cur_cols     <= l1_cols;
                    cur_wt_base  <= l1_wt_base;
                    cur_bias_base <= l1_bias_base;
                    cur_relu_en  <= 1'b1;  // ReLU ON for Layer 1
                    row_tile     <= 0;
                    cop_done     <= 0;
                    valid_result <= 0;
                    sub_cnt      <= 0;
                    state        <= S_BIAS_LOAD;
                end
                
                S_BIAS_LOAD: begin
                    // Request bias words for each of the ROWS
                    // Latency: req @ sub_cnt, capture @ sub_cnt + 2
                    if (sub_cnt < ROWS) begin
                        bias_raddr <= cur_bias_base[7:0] + row_tile + sub_cnt;
                    end
                    
                    if (sub_cnt >= 2 && sub_cnt <= ROWS + 1) begin
                        systolic_bias_packed[(sub_cnt-2)*32 +: 32] <= bias_rdata;
                    end
                    
                    if (sub_cnt == ROWS + 1) begin
                        $display("COP: Transition S_BIAS_LOAD -> S_TILE_LOAD, row_tile=%d", row_tile);
                        systolic_flush <= 1;
                        sub_cnt <= 0; col_tile <= 0;
                        state <= S_TILE_LOAD;
                    end else begin
                        sub_cnt <= sub_cnt + 1;
                    end
                end

                S_TILE_LOAD: begin
                    // Load WORDS_PER_TILE words of activations and WORDS_PER_TILE * ROWS words of weights
                    // Request weight word 's' at sub_cnt = s
                    // Capture weight word 's' at sub_cnt = s + 2
                    
                    // 1. Requests
                    if (sub_cnt < (COLS >> 2) * ROWS) begin
                        // Activations: only first (COLS >> 2) words
                        if (sub_cnt < (COLS >> 2)) in_raddr <= col_tile + sub_cnt;
                        
                        // Weights: (COLS >> 2) words for each of the ROWS
                        wt_raddr <= cur_wt_base[14:0] + (row_tile + (sub_cnt / (COLS >> 2))) * (cur_cols >> 2) + col_tile + (sub_cnt % (COLS >> 2));
                    end

                    // 2. Captures
                    if (sub_cnt >= 2 && sub_cnt < 2 + (COLS >> 2)) begin
                        systolic_a_data[(sub_cnt - 2)*32 +: 32] <= in_rdata;
                    end
                    
                    if (sub_cnt >= 2 && sub_cnt <= (COLS >> 2)*ROWS + 1) begin
                        // Capture weight word requested at sub_cnt - 2
                        prev_r = (sub_cnt - 2) / (COLS >> 2);
                        prev_w = (sub_cnt - 2) % (COLS >> 2);
                        systolic_w_data_packed[(prev_r*COLS*8) + prev_w*32 +: 32] <= ((row_tile + prev_r) < cur_rows) ? wt_rdata : 32'd0;
                    end

                    // 3. State transition
                    if (sub_cnt == (COLS >> 2)*ROWS + 1) begin
                        systolic_w_load <= 1;
                        systolic_a_valid <= 1;
                        sub_cnt <= 0;
                        if (col_tile + (COLS >> 2) < (cur_cols >> 2)) begin
                            col_tile <= col_tile + (COLS >> 2);
                            state <= S_TILE_LOAD;
                        end else begin
                            $display("COP: Transition S_TILE_LOAD -> S_COLLECT_WAIT, col_tile=%d", col_tile);
                            state <= S_COLLECT_WAIT;
                        end
                    end else begin
                        sub_cnt <= sub_cnt + 1;
                    end
                end
                
                S_COLLECT_WAIT: if (systolic_valid_out) begin 
                    $display("COP: Transition S_COLLECT_WAIT -> S_COLLECT_WRITE at time %t", $time);
                    state <= S_COLLECT_WRITE; sub_cnt <= 0; 
                end
                
                S_COLLECT_WRITE: begin
                    if (sub_cnt < ROWS) begin
                        if ((row_tile + sub_cnt) < cur_rows) begin
                            out_we <= 1; out_waddr <= row_tile + sub_cnt;
                            out_wdata <= systolic_result_packed[sub_cnt*32 +: 32];
                        end
                        sub_cnt <= sub_cnt + 1;
                    end else begin
                        if (row_tile + ROWS >= cur_rows) begin
                            if (layer_num == 0) begin
                                $display("COP: Layer 1 COMPLETE, transition to S_SCALE_ADDR");
                                state <= S_SCALE_ADDR;
                                scale_cnt <= 0; scale_byte_idx <= 0;
                                scale_word_idx <= 0; scale_word_buf <= 0;
                            end else begin
                                $display("COP: Layer 2 COMPLETE, transition to S_ARGMAX_PREP");
                                state <= S_ARGMAX_PREP;
                                sub_cnt <= 0;
                            end
                        end else begin
                            row_tile <= row_tile + ROWS;
                            state <= S_BIAS_LOAD; sub_cnt <= 0;
                        end
                    end
                end
                
                S_SCALE_ADDR: begin
                    out_raddr <= scale_cnt;
                    state <= S_SCALE_WAIT;
                end
                
                S_SCALE_WAIT: begin
                    state <= S_SCALE_PROC;
                end
                
                S_SCALE_PROC: begin
                    case (scale_byte_idx)
                        2'd0: scale_word_buf[7:0]   <= clamped;
                        2'd1: scale_word_buf[15:8]  <= clamped;
                        2'd2: scale_word_buf[23:16] <= clamped;
                        2'd3: scale_word_buf[31:24] <= clamped;
                    endcase
                    
                    if (scale_byte_idx == 2'd3) begin
                        in_rwe <= 1;
                        in_rwaddr <= scale_word_idx;
                        in_rwdata <= {clamped, scale_word_buf[23:0]};
                        scale_word_idx <= scale_word_idx + 1;
                        scale_byte_idx <= 0;
                    end else begin
                        scale_byte_idx <= scale_byte_idx + 1;
                    end
                    
                    scale_cnt <= scale_cnt + 1;
                    if (scale_cnt + 1 >= l1_rows[7:0]) begin
                        $display("COP: Scaling COMPLETE, transition to S_L2_SETUP");
                        state <= S_L2_SETUP;
                    end else begin
                        state <= S_SCALE_ADDR;
                    end
                end
                
                S_L2_SETUP: begin
                    layer_num    <= 1;
                    cur_rows     <= l2_rows;
                    cur_cols     <= l2_cols;
                    cur_wt_base  <= l2_wt_base;
                    cur_bias_base <= l2_bias_base;
                    cur_relu_en  <= 1'b0;
                    row_tile     <= 0;
                    sub_cnt      <= 0;
                    $display("COP: START Layer 2");
                    state        <= S_BIAS_LOAD;
                end
                
                S_ARGMAX_PREP: begin
                    if (sub_cnt <= 9) begin
                        out_raddr <= sub_cnt;
                    end
                    if (sub_cnt >= 2 && sub_cnt <= 11) begin
                        argmax_scores_packed[(sub_cnt-2)*32 +: 32] <= out_rdata;
                    end
                    if (sub_cnt == 11) begin
                        $display("COP: Transition S_ARGMAX_PREP -> S_ARGMAX");
                        argmax_start <= 1; state <= S_ARGMAX;
                    end else begin
                        sub_cnt <= sub_cnt + 1;
                    end
                end
                
                S_ARGMAX: if (argmax_valid) begin
                    $display("COP: ALL COMPLETE, winner=%d, score=%d", argmax_winner_idx, argmax_winner_val);
                    if (!is_cpu_trigger) begin
                        class_index <= argmax_winner_idx;
                        max_score <= argmax_winner_val;
                        valid_result <= 1;
                    end
                    cop_done <= 1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ---- Cycle counter ----
    reg [31:0] cycle_counter;
    reg [31:0] execution_cycles;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_counter <= 0;
            execution_cycles <= 0;
        end else begin
            cycle_counter <= cycle_counter + 1;
            if (state != S_IDLE)
                execution_cycles <= execution_cycles + 1;
            else if (start_reg)
                execution_cycles <= 0; // Reset on start
        end
    end

    // ---- MMIO reads ----
    always @(*) begin
        cop_rdata = 32'd0;
        if (cop_re) begin
            case (cop_addr[11:0])
                12'h000: cop_rdata = {31'd0, start_reg};
                12'h004: cop_rdata = {31'd0, (state != S_IDLE || start_reg)};
                12'h010: cop_rdata = l1_rows;
                12'h014: cop_rdata = l1_cols;
                12'h020: cop_rdata = l2_rows;
                12'h024: cop_rdata = l2_cols;
                12'h028: cop_rdata = {27'd0, inter_shift};
                12'h100: cop_rdata = {31'd0, (state != S_IDLE)}; 
                12'h200: cop_rdata = cycle_counter;
                12'h328: cop_rdata = hw_cycles_res;
                12'h32C: cop_rdata = sw_cycles_res;
                12'h330: cop_rdata = execution_cycles;
                12'h300: cop_rdata = argmax_scores_packed[0*32 +: 32];
                12'h304: cop_rdata = argmax_scores_packed[1*32 +: 32];
                12'h308: cop_rdata = argmax_scores_packed[2*32 +: 32];
                12'h30C: cop_rdata = argmax_scores_packed[3*32 +: 32];
                12'h310: cop_rdata = argmax_scores_packed[4*32 +: 32];
                12'h314: cop_rdata = argmax_scores_packed[5*32 +: 32];
                12'h318: cop_rdata = argmax_scores_packed[6*32 +: 32];
                12'h31C: cop_rdata = argmax_scores_packed[7*32 +: 32];
                12'h320: cop_rdata = argmax_scores_packed[8*32 +: 32];
                12'h324: cop_rdata = argmax_scores_packed[9*32 +: 32];
                default: cop_rdata = 32'd0;
            endcase
        end
    end
    assign cop_busy = (state != S_IDLE);

endmodule
