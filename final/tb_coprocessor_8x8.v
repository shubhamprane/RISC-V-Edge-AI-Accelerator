`timescale 1ns / 1ps

module tb_coprocessor_8x8;
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

    coprocessor_top #(8, 8) uut (
        .clk(clk), .rst(rst), .cop_addr(cop_addr), .cop_wdata(cop_wdata),
        .cop_we(cop_we), .cop_re(cop_re), .uart_ready(uart_ready),
        .in_wclk(clk), .in_we(in_we), .in_waddr(in_waddr), .in_wdata(in_wdata),
        .cop_rdata(cop_rdata), .cop_busy(cop_busy), .cop_done(cop_done),
        .valid_result(valid_result), .class_index(class_index), .max_score(max_score)
    );

    always #5 clk = ~clk;

    integer i;
    initial begin
        clk = 0; rst = 1; cop_addr = 0; cop_wdata = 0; cop_we = 0; cop_re = 0;
        uart_ready = 0; in_we = 0; in_waddr = 0; in_wdata = 0;
        #20 rst = 0;

        // Configure coprocessor MMIO
        @(posedge clk);
        cop_we = 1; cop_addr = 12'h010; cop_wdata = 32'd8; // l1_rows = 8
        @(posedge clk); cop_addr = 12'h014; cop_wdata = 32'd8; // l1_cols = 8
        @(posedge clk); cop_addr = 12'h020; cop_wdata = 32'd10; // l2_rows = 10
        @(posedge clk); cop_addr = 12'h024; cop_wdata = 32'd8; // l2_cols = 8
        @(posedge clk); cop_we = 0;

        // Load synthetic inputs (8 bytes = 2 words)
        for (i=0; i<2; i=i+1) begin
            @(posedge clk);
            in_we = 1; in_waddr = i; in_wdata = 32'h01010101;
        end
        @(posedge clk); in_we = 0;

        // Trigger inference
        @(posedge clk);
        uart_ready = 1;
        @(posedge clk);
        uart_ready = 0;

        // Wait for result with timeout
        begin : wait_block
            integer timeout;
            timeout = 0;
            while (!valid_result && timeout < 50000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (valid_result) begin
                $display("PASS: Coprocessor 8x8 (class_index=%d, max_score=%d)", class_index, max_score);
            end else begin
                $display("FAIL: Timeout");
            end
        end
        
        #100 $finish;
    end
endmodule
