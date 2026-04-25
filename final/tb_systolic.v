`timescale 1ns/1ps
module tb_systolic;
    reg clk, rst, flush, a_valid, w_load, relu_en;
    reg [31:0] a_data;
    reg [4*8*4-1:0] w_data_packed;
    reg [4*32-1:0] bias_packed;
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
        
        w_load = 1;
        // Row 0: all 50. Row 1-3: all 1.
        w_data_packed[31:0]   = {8'd50, 8'd50, 8'd50, 8'd50};
        w_data_packed[63:32]  = {8'd1, 8'd1, 8'd1, 8'd1};
        w_data_packed[95:64]  = {8'd1, 8'd1, 8'd1, 8'd1};
        w_data_packed[127:96] = {8'd1, 8'd1, 8'd1, 8'd1};
        #10 w_load = 0;
        
        flush = 1; #10 flush = 0;
        a_valid = 1; a_data = {8'd1, 8'd1, 8'd1, 8'd1};
        #40 a_valid = 0; // 4 cycles * 4 lanes = 16 elements
        
        wait(valid_out);
        #10;
        if (result_row_packed[31:0] == 800 && result_row_packed[63:32] == 16)
            $display("TB_SYSTOLIC: PASS");
        else
            $display("TB_SYSTOLIC: FAIL (Row0=%d, Row1=%d)", result_row_packed[31:0], result_row_packed[63:32]);
        
        #100 $finish;
    end
endmodule
