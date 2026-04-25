`timescale 1ns / 1ps

module systolic_array #(
    parameter ROWS = 8,
    parameter COLS = 8
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,
    input  wire        a_valid,
    input  wire [8*COLS-1:0] a_data,
    input  wire        w_load,
    input  wire [ROWS*8*COLS-1:0] w_data_packed,
    input  wire [ROWS*32-1:0] bias_packed,
    input  wire        relu_en,
    output wire [ROWS*32-1:0] result_row_packed,
    output reg         valid_out
);

    wire [8*COLS-1:0] w_data [0:ROWS-1];
    wire signed [31:0] bias [0:ROWS-1];
    reg  signed [31:0] result_row [0:ROWS-1];
    
    genvar g;
    generate
        for (g=0; g<ROWS; g=g+1) begin : UNPACK_WB
            assign w_data[g] = w_data_packed[g*8*COLS +: 8*COLS];
            assign bias[g]   = $signed(bias_packed[g*32 +: 32]);
            assign result_row_packed[g*32 +: 32] = result_row[g];
        end
    endgenerate

    wire signed [7:0] a_in_unpacked [0:COLS-1];
    genvar i, j;
    generate
        for (i = 0; i < COLS; i = i + 1) begin : UNPACK_A
            assign a_in_unpacked[i] = $signed(a_data[8*i +: 8]);
        end
    endgenerate

    wire signed [31:0] pe_acc [0:ROWS-1][0:COLS-1];
    
    generate
        for (i = 0; i < ROWS; i = i + 1) begin : ROW_GEN
            for (j = 0; j < COLS; j = j + 1) begin : COL_GEN
                wire signed [7:0] w_in = $signed(w_data[i][8*j +: 8]);
                wire signed [7:0] a_in_current;
                wire v_in_current;
                
                assign a_in_current = a_in_unpacked[j];
                assign v_in_current = a_valid;
                
                pe u_pe (
                    .clk(clk), .rst(rst), .flush(flush), .w_load(w_load),
                    .w_in(w_in), .a_in(a_in_current), .a_valid(v_in_current), .acc(pe_acc[i][j])
                );
            end
        end
    endgenerate

    reg a_valid_q;
    always @(posedge clk or posedge rst) begin
        if (rst) a_valid_q <= 0;
        else a_valid_q <= a_valid;
    end

    wire signed [31:0] row_sum [0:ROWS-1];
    generate
        for (i = 0; i < ROWS; i = i + 1) begin : SUM
            reg signed [31:0] sum_tmp;
            integer m;
            always @(*) begin
                sum_tmp = 0;
                for (m = 0; m < COLS; m = m + 1) begin
                    sum_tmp = sum_tmp + pe_acc[i][m];
                end
            end
            assign row_sum[i] = sum_tmp;
        end
    endgenerate

    integer k;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out <= 0;
            for (k = 0; k < ROWS; k = k + 1) result_row[k] <= 0;
        end else begin
            valid_out <= 0;
            if (a_valid_q && !a_valid) begin
                valid_out <= 1;
                for (k = 0; k < ROWS; k = k + 1) begin
                    if (relu_en && (row_sum[k] + bias[k] < 0))
                        result_row[k] <= 0;
                    else
                        result_row[k] <= row_sum[k] + bias[k];
                end
            end
        end
    end
endmodule
