`timescale 1ns / 1ps

module tb_top;
    reg clk;
    reg reset;
    reg rx;
    wire [15:0] led;
    wire [7:0] seg_anode;
    wire [6:0] seg_cathode;

    top_fpga dut (
        .clk(clk), .reset(reset), .rx(rx),
        .led(led), .seg_anode(seg_anode), .seg_cathode(seg_cathode)
    );

    always #5 clk = ~clk;

    always @(posedge dut.slow_clk) begin
        if (!reset) $display("PC: %h", dut.current_pc);
    end

    initial begin
        clk = 0; reset = 1; rx = 1;
        #155 reset = 0;
        
        // Wait for inference to complete (approx 5M ns)
        #5000000;
        
        $display("TB_TOP: LED = 16'h%h", led);
        $display("TB_TOP: SEGS = AN:%h CAT:%h", seg_anode, seg_cathode);
        
        if (led != 16'h0000 || seg_anode != 8'hFF)
            $display("TB_TOP: PASS");
        else
            $display("TB_TOP: FAIL (No activity)");
            
        $finish;
    end
endmodule
