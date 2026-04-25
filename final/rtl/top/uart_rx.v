`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid
);

    localparam BAUD_TICK_MAX = CLK_FREQ / (BAUD_RATE * 16);
    reg [$clog2(BAUD_TICK_MAX):0] tick_cnt;
    reg baud_tick;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tick_cnt <= 0;
            baud_tick <= 0;
        end else if (tick_cnt == BAUD_TICK_MAX - 1) begin
            tick_cnt <= 0;
            baud_tick <= 1;
        end else begin
            tick_cnt <= tick_cnt + 1;
            baud_tick <= 0;
        end
    end

    localparam S_IDLE = 2'd0, S_START = 2'd1, S_DATA = 2'd2, S_STOP = 2'd3;
    reg [1:0] state;
    reg [3:0] sample_cnt;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            sample_cnt <= 0;
            bit_cnt <= 0;
            shift_reg <= 0;
            rx_data <= 0;
            rx_valid <= 0;
        end else begin
            rx_valid <= 0;
            if (baud_tick) begin
                case (state)
                    S_IDLE: begin
                        if (rx == 0) begin // Start bit detected
                            state <= S_START;
                            sample_cnt <= 0;
                        end
                    end
                    S_START: begin
                        if (sample_cnt == 7) begin
                            if (rx == 0) begin
                                state <= S_DATA;
                                sample_cnt <= 0;
                                bit_cnt <= 0;
                            end else state <= S_IDLE;
                        end else sample_cnt <= sample_cnt + 1;
                    end
                    S_DATA: begin
                        if (sample_cnt == 15) begin
                            shift_reg <= {rx, shift_reg[7:1]};
                            sample_cnt <= 0;
                            if (bit_cnt == 7) state <= S_STOP;
                            else bit_cnt <= bit_cnt + 1;
                        end else sample_cnt <= sample_cnt + 1;
                    end
                    S_STOP: begin
                        if (sample_cnt == 15) begin
                            if (rx == 1) begin
                                rx_data <= shift_reg;
                                rx_valid <= 1;
                            end
                            state <= S_IDLE;
                        end else sample_cnt <= sample_cnt + 1;
                    end
                endcase
            end
        end
    end

endmodule
