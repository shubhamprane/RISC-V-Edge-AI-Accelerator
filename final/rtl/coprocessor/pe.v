`timescale 1ns / 1ps

module pe (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,
    input  wire        w_load,
    input  wire signed [7:0]  w_in,
    input  wire signed [7:0]  a_in,
    input  wire        a_valid,
    output reg  signed [31:0] acc
);
    reg signed [7:0] w_reg;
    always @(posedge clk or posedge rst) begin
        if (rst || flush) acc <= 0;
        else begin
            if (a_valid) acc <= acc + a_in * (w_load ? w_in : w_reg);
            if (w_load)  w_reg <= w_in;
        end
    end
endmodule
