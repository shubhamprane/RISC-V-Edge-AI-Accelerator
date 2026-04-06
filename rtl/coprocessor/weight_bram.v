`timescale 1ns / 1ps

module weight_bram #(
    parameter DEPTH = 16384, // 16K words = 64KB (Holds layer 1 & 2 weights)
    parameter WIDTH = 32     // 4 packed INT8 values per word
) (
    input  wire clk,
    
    // Write port (Used by CPU MMIO during initialization)
    input  wire we,
    input  wire [13:0] waddr,
    input  wire [WIDTH-1:0] wdata,
    
    // Read port (Used by MAC Engine / Systolic Array)
    input  wire re,
    input  wire [13:0] raddr,
    output reg  [WIDTH-1:0] rdata
);

    (* ram_style = "block" *)
    reg [WIDTH-1:0] ram [0:DEPTH-1];

    // Initialize with Python-generated hex file
    initial begin
        $readmemh("weights_layer1.mem", ram);
    end

    always @(posedge clk) begin
        if (we) begin
            ram[waddr] <= wdata;
        end
        if (re) begin
            rdata <= ram[raddr];
        end
    end

endmodule