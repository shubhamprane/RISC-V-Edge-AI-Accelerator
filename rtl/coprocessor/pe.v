`timescale 1ns / 1ps

module pe (
    input  wire clk, 
    input  wire rst,
    input  wire signed [7:0]  a_in,   // Activation flows right
    input  wire signed [7:0]  b_in,   // Weight flows down
    input  wire signed [31:0] acc_in, // Accumulator flows down (typically)
    
    output reg  signed [7:0]  a_out,
    output reg  signed [7:0]  b_out,
    output reg  signed [31:0] acc_out
);

    always @(posedge clk) begin
        if (rst) begin
            a_out   <= 8'd0;
            b_out   <= 8'd0;
            acc_out <= 32'd0;
        end else begin
            a_out   <= a_in;
            b_out   <= b_in;
            // The core DSP operation
            acc_out <= acc_in + (a_in * b_in); 
        end
    end

endmodule