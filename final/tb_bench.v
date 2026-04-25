`timescale 1ns / 1ps

module tb_bench;
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

    always #10 clk = ~clk; // 50 MHz clock

    initial begin
        clk = 0; reset = 1; rx = 1;
        #100 reset = 0;
        
        // Wait for Done signal at 0x00001F10 in DMEM
        // dmem[0x1F10/4] = dmem[1992]
        // In my processor, dmem is addressed by byte. 
        // 0x1F10 in dmem_bram.
        
        // Watch for memory write to 0x1F10
        wait(dut.DMEM.we && dut.DMEM.waddr == 32'h00001F10);
        #100;
        $display("--------------------------------------------------");
        $display("SPEEDUP BENCHMARK RESULTS");
        $display("Hardware Cycles: %d", dut.DMEM.dmem[1984]); // 0x1F00 / 4
        $display("Software Cycles: %d", dut.DMEM.dmem[1985]); // 0x1F04 / 4
        $display("Architectural Speedup: %0.2f x", (1.0 * dut.DMEM.dmem[1985]) / dut.DMEM.dmem[1984]);
        $display("--------------------------------------------------");
        $finish;
    end
endmodule
