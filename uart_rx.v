`timescale 1ns / 1ps

module uart_rx #(
    // Default for 100MHz clock and 115200 baud rate (100,000,000 / 115200 = ~868)
    parameter CLKS_PER_BIT = 868 
)(
    input  wire clk,
    input  wire rst,
    input  wire rxd,
    
    output reg  [7:0] byte_out,
    output reg        byte_valid,
    output reg        frame_error
);

    localparam s_IDLE  = 3'b000;
    localparam s_START = 3'b001;
    localparam s_DATA  = 3'b010;
    localparam s_STOP  = 3'b011;
    localparam s_CLEAN = 3'b100;

    reg [2:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;   // 8 bits total (0 to 7)
    reg [7:0]  shift_reg;

    always @(posedge clk) begin
        if (rst) begin
            state       <= s_IDLE;
            clk_count   <= 0;
            bit_index   <= 0;
            byte_out    <= 0;
            byte_valid  <= 1'b0;
            frame_error <= 1'b0;
            shift_reg   <= 0;
        end else begin
            case (state)
                s_IDLE: begin
                    byte_valid  <= 1'b0;
                    frame_error <= 1'b0;
                    clk_count   <= 0;
                    bit_index   <= 0;
                    
                    // Detect falling edge of Start Bit
                    if (rxd == 1'b0) begin
                        state <= s_START;
                    end
                end

                s_START: begin
                    if (clk_count == (CLKS_PER_BIT / 2)) begin
                        if (rxd == 1'b0) begin
                            // Still low at the midpoint, valid start bit
                            clk_count <= 0;
                            state     <= s_DATA;
                        end else begin
                            // False alarm (glitch)
                            state     <= s_IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                s_DATA: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        shift_reg[bit_index] <= rxd; // Sample the data bit
                        
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            state     <= s_STOP;
                        end
                    end
                end

                s_STOP: begin
                    // Wait for the middle of the stop bit
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        if (rxd == 1'b1) begin
                            // Valid Stop Bit
                            frame_error <= 1'b0;
                            byte_out    <= shift_reg;
                            byte_valid  <= 1'b1;
                            state       <= s_CLEAN;
                        end else begin
                            // Framing Error (Stop bit not detected)
                            frame_error <= 1'b1;
                            state       <= s_IDLE; 
                        end
                    end
                end

                s_CLEAN: begin
                    // Pulse byte_valid for exactly 1 clock cycle
                    byte_valid <= 1'b0;
                    state      <= s_IDLE;
                end
                
                default: state <= s_IDLE;
            endcase
        end
    end

endmodule