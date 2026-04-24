`timescale 1ns / 1ps

module tb_systolic_corrected;
    reg clk;
    reg rst;
    reg flush;
    reg a_valid;
    reg [8*4-1:0] a_data;
    reg w_load;
    reg [4*8*4-1:0] w_data_packed;
    reg [4*32-1:0] bias_packed;
    reg relu_en;
    wire [4*32-1:0] result_row_packed;
    wire valid_out;

    systolic_array #(4, 4) dut (
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
        // Inputs: [1, 2, 3, 4]
        // Weights Row 0: [10, 10, 10, 10] -> acc = 10*(1+2+3+4) = 100
        @(negedge clk);
        w_load = 1; a_valid = 1;
        w_data_packed[31:0] = {8'd10, 8'd10, 8'd10, 8'd10};
        a_data = {8'd4, 8'd3, 8'd2, 8'd1}; // packed j=3,2,1,0
        @(posedge clk); #1; w_load = 0; a_valid = 0;

        // Tile 1:
        // Inputs: [5, 6, 7, 8]
        // Weights Row 0: [2, 2, 2, 2] -> acc = 100 + 2*(5+6+7+8) = 100 + 2*26 = 152
        @(negedge clk);
        w_load = 1; a_valid = 1;
        w_data_packed[31:0] = {8'd2, 8'd2, 8'd2, 8'd2};
        a_data = {8'd8, 8'd7, 8'd6, 8'd5};
        @(posedge clk); #1; w_load = 0; a_valid = 0;

        wait(valid_out);
        #1;
        if (result_row_packed[31:0] === 152) $display("PASS: Systolic Corrected (Row0=152)");
        else $display("FAIL: Systolic Corrected (Row0=%d)", result_row_packed[31:0]);

        #100 $finish;
    end
endmodule
