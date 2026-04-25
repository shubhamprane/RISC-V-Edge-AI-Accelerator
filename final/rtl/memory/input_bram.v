`timescale 1ns / 1ps
module input_bram #(
    parameter DEPTH = 256,
    parameter WIDTH = 32
) (
    // Write port (100 MHz UART domain)
    input wire wclk,
    input wire we,
    input wire [7:0] waddr,
    input wire [WIDTH-1:0] wdata,
    // Read/Write port (10 MHz coprocessor domain)
    input wire rclk,
    input wire re,
    input wire rwe,            // coprocessor write enable
    input wire [7:0] raddr,    // coprocessor address (used for both read and write)
    output reg [WIDTH-1:0] rdata,
    input wire [WIDTH-1:0] rwdata // coprocessor write data
);
    (* ram_style = "block" *)
    reg [WIDTH-1:0] ram [0:DEPTH-1];

    initial begin
        $readmemh("input.mem", ram);
    end

    // Port A: UART writes — clocked by fast clock (100 MHz)
    always @(posedge wclk) begin
        if (we) ram[waddr] <= wdata;
    end

    // Port B: Coprocessor read/write — clocked by slow clock (10 MHz)
    always @(posedge rclk) begin
        if (rwe) begin
            ram[raddr] <= rwdata;
            if (re) rdata <= rwdata; // write-first behavior
        end else begin
            if (re) rdata <= ram[raddr];
        end
    end
endmodule
