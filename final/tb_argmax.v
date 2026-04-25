`timescale 1ns/1ps
module tb_argmax;
    reg clk, rst, start;
    reg [10*32-1:0] scores_packed;
    wire [3:0] winner_idx;
    wire signed [31:0] winner_val;
    wire valid;

    argmax_unit #(10, 32) uut (
        .clk(clk), .rst(rst), .start(start), .scores_packed(scores_packed),
        .winner_idx(winner_idx), .winner_val(winner_val), .valid(valid)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0; rst = 1; start = 0; scores_packed = 0;
        #20 rst = 0;
        
        repeat(5) @(posedge clk);

        // Test 1: Max at index 7
        @(negedge clk);
        for (integer i=0; i<10; i=i+1) scores_packed[i*32 +: 32] = i*10;
        scores_packed[7*32 +: 32] = 500;
        start = 1;
        @(posedge clk); #1; start = 0;
        
        wait(valid);
        #1;
        if (winner_idx === 7 && winner_val === 500) $display("PASS: Argmax Test 1 (winner=7, val=500)");
        else $display("FAIL: Argmax Test 1 (winner=%d, val=%d)", winner_idx, winner_val);
        
        @(posedge clk);
        // Test 2: All negatives, max is -1 at index 3
        @(negedge clk);
        for (integer i=0; i<10; i=i+1) scores_packed[i*32 +: 32] = -100 - i;
        scores_packed[3*32 +: 32] = -1;
        start = 1;
        @(posedge clk); #1; start = 0;
        wait(valid);
        #1;
        if (winner_idx === 3 && winner_val === -1) $display("PASS: Argmax Test 2 (winner=3, val=-1)");
        else $display("FAIL: Argmax Test 2 (winner=%d, val=%d)", winner_idx, winner_val);
        
        @(posedge clk);
        // Test 3: Equal values at 0 and 9 (max=100) -> Should pick 0 (lower index)
        @(negedge clk);
        for (integer i=0; i<10; i=i+1) scores_packed[i*32 +: 32] = 0;
        scores_packed[0*32 +: 32] = 100;
        scores_packed[9*32 +: 32] = 100;
        start = 1;
        @(posedge clk); #1; start = 0;
        wait(valid);
        #1;
        if (winner_idx === 0 && winner_val === 100) $display("PASS: Argmax Test 3 (winner=0, val=100)");
        else $display("FAIL: Argmax Test 3 (winner=%d, val=%d)", winner_idx, winner_val);

        #100 $finish;
    end
endmodule
