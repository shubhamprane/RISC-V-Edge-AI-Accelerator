`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output reg        tx,
    output reg        tx_busy
);

    localparam CLK_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;
    
    reg [1:0]  state;
    reg [31:0] clk_cnt;
    reg [2:0]  bit_cnt;
    reg [7:0]  tx_shift;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= S_IDLE;
            tx       <= 1'b1;
            tx_busy  <= 1'b0;
            clk_cnt  <= 0;
            bit_cnt  <= 0;
            tx_shift <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    if (tx_start) begin
                        state    <= S_START;
                        tx_shift <= tx_data;
                        tx_busy  <= 1'b1;
                        clk_cnt  <= 0;
                    end else begin
                        tx_busy  <= 1'b0;
                    end
                end
                
                S_START: begin
                    tx <= 1'b0;
                    if (clk_cnt < CLK_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        state   <= S_DATA;
                        bit_cnt <= 0;
                    end
                end
                
                S_DATA: begin
                    tx <= tx_shift[0];
                    if (clk_cnt < CLK_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        tx_shift <= {1'b0, tx_shift[7:1]};
                        if (bit_cnt < 7) begin
                            bit_cnt <= bit_cnt + 1;
                        end else begin
                            state <= S_STOP;
                        end
                    end
                end
                
                S_STOP: begin
                    tx <= 1'b1;
                    if (clk_cnt < CLK_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        state   <= S_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
