`timescale 1ns / 1ps

module tb_pe;
    reg clk;
    reg rst;
    reg flush;
    reg w_load;
    reg signed [7:0] w_in;
    reg signed [7:0] a_in;
    reg a_valid;
    wire signed [31:0] acc;

    pe uut (
        .clk(clk), .rst(rst), .flush(flush), .w_load(w_load),
        .w_in(w_in), .a_in(a_in), .a_valid(a_valid), .acc(acc)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0; rst = 1; flush = 0; w_load = 0; w_in = 0; a_in = 0; a_valid = 0;
        #20 rst = 0;

        // Test 1: Simple MAC (2 * 10 + 2 * 20 = 60)
        @(negedge clk);
        w_in = 2; w_load = 1;
        a_in = 10; a_valid = 1; // Single cycle load and accumulate!
        @(posedge clk); #1; w_load = 0;
        
        a_in = 20; a_valid = 1;
        @(posedge clk); #1; a_valid = 0;
        
        if (acc === 60) $display("PASS: PE Test 1 (acc=60)");
        else $display("FAIL: PE Test 1 (acc=%d)", acc);

        // Test 2: Flush
        flush = 1; @(posedge clk); #1; flush = 0;
        if (acc === 0) $display("PASS: PE Test 2 (flush)");
        else $display("FAIL: PE Test 2 (acc=%d)", acc);

        // Test 3: Signed ( -3 * 10 + (-3) * (-5) = -30 + 15 = -15)
        @(negedge clk);
        w_in = -3; w_load = 1;
        a_in = 10; a_valid = 1;
        @(posedge clk); #1; w_load = 0;
        
        a_in = -5; a_valid = 1;
        @(posedge clk); #1; a_valid = 0;
        
        if (acc === -15) $display("PASS: PE Test 3 (acc=-15)");
        else $display("FAIL: PE Test 3 (acc=%d)", acc);

        #100 $finish;
    end
endmodule
