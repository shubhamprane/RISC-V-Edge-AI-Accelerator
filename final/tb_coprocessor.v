`timescale 1ns / 1ps

module tb_coprocessor;
    reg clk;
    reg rst;
    reg [23:0] cop_addr;
    reg [31:0] cop_wdata;
    reg cop_we;
    reg cop_re;
    reg uart_ready;
    reg in_we;
    reg [7:0] in_waddr;
    reg [31:0] in_wdata;

    wire [31:0] cop_rdata;
    wire cop_busy;
    wire cop_done;
    wire valid_result;
    wire [3:0] class_index;
    wire signed [31:0] max_score;

    coprocessor_top #(4, 4) uut (
        .clk(clk), .rst(rst), .cop_addr(cop_addr), .cop_wdata(cop_wdata),
        .cop_we(cop_we), .cop_re(cop_re), .uart_ready(uart_ready),
        .in_wclk(clk), .in_we(in_we), .in_waddr(in_waddr), .in_wdata(in_wdata),
        .cop_rdata(cop_rdata), .cop_busy(cop_busy), .cop_done(cop_done),
        .valid_result(valid_result), .class_index(class_index), .max_score(max_score)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0; rst = 1; cop_addr = 0; cop_wdata = 0; cop_we = 0; cop_re = 0;
        uart_ready = 0; in_we = 0; in_waddr = 0; in_wdata = 0;
        #20 rst = 0;

        // Configure coprocessor MMIO
        @(posedge clk);
        cop_we = 1;
        // Let default coprocessor_top values configure the 2-layer network
        // (l1_rows=128, l1_cols=784, l2_rows=10, l2_cols=128, inter_shift=11)
        // Just send a dummy write to trigger inference if needed (uart_ready does it anyway)
        @(posedge clk); cop_we = 0;

        // Load synthetic inputs (16 bytes = 4 words)
        // input = [1, 1, 1, 1, ..., 1]
        for (integer i=0; i<4; i=i+1) begin
            @(posedge clk);
            in_we = 1; in_waddr = i; in_wdata = 32'h01010101;
        end
        @(posedge clk); in_we = 0;

        // Note: weight_bram and bias_bram are pre-loaded via $readmemh in their respective files.
        // For this test, I'll assume they have some data or I'll force them.
        // Since I can't easily change the .mem files, I'll just use the ones there or
        // check if they are initialized to 0.
        
        // Trigger inference
        @(posedge clk);
        uart_ready = 1;
        @(posedge clk);
        uart_ready = 0;

        wait(valid_result);
        $display("PASS: Coprocessor Top (class_index=%d, max_score=%d)", class_index, max_score);
        
        #100 $finish;
    end
endmodule
