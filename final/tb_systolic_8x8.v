`timescale 1ns / 1ps

module tb_systolic_8x8;
    reg clk;
    reg rst;
    reg flush;
    reg a_valid;
    reg [8*8-1:0] a_data;
    reg w_load;
    reg [8*8*8-1:0] w_data_packed;
    reg [8*32-1:0] bias_packed;
    reg relu_en;
    wire [8*32-1:0] result_row_packed;
    wire valid_out;

    systolic_array #(8, 8) dut (
        .clk(clk), .rst(rst), .flush(flush), .a_valid(a_valid), .a_data(a_data),
        .w_load(w_load), .w_data_packed(w_data_packed), .bias_packed(bias_packed), .relu_en(relu_en),
        .result_row_packed(result_row_packed), .valid_out(valid_out)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0; rst = 1; flush = 0; a_valid = 0; w_load = 0; relu_en = 0;
        w_data_packed = 0; bias_packed = 0;
        #20 rst = 0;

        // Tile 0:
        // Inputs: [1, 1, 1, 1, 1, 1, 1, 1]
        // Weights Row 0: [1, 1, 1, 1, 1, 1, 1, 1] -> acc = 8
        @(negedge clk);
        w_load = 1; a_valid = 1;
        w_data_packed[63:0] = 64'h0101010101010101;
        a_data = 64'h0101010101010101;
        @(posedge clk); #1; w_load = 0; a_valid = 0;

        wait(valid_out);
        #1;
        if (result_row_packed[31:0] === 8) $display("PASS: Systolic 8x8 (Row0=8)");
        else $display("FAIL: Systolic 8x8 (Row0=%d)", result_row_packed[31:0]);

        #100 $finish;
    end
endmodule
