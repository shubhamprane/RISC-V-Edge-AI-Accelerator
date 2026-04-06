`timescale 1ns / 1ps

module bias_bram #(
    parameter DEPTH = 128,  // Enough for 128 neurons
    parameter WIDTH = 32
) (
    input  wire clk,
    input  wire we,
    input  wire [6:0] waddr,
    input  wire [WIDTH-1:0] wdata,
    input  wire re,
    input  wire [6:0] raddr,
    output reg  [WIDTH-1:0] rdata
);

    (* ram_style = "block" *)
    reg [WIDTH-1:0] ram [0:DEPTH-1];

    initial begin
        $readmemh("bias_layer1.mem", ram);
    end

    always @(posedge clk) begin
        if (we) ram[waddr] <= wdata;
        if (re) rdata <= ram[raddr];
    end

endmodule