`timescale 1ns / 1ps

module uart_input_buffer (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output reg  [7:0]  bram_waddr,
    output reg  [31:0] bram_wdata,
    output reg         bram_we,
    output reg         buf_ready
);

    reg [31:0] word_buffer;
    reg [1:0]  byte_cnt;
    reg [9:0]  total_byte_cnt;

    reg buf_ready_next;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            word_buffer <= 0;
            byte_cnt <= 0;
            total_byte_cnt <= 0;
            bram_waddr <= 0;
            bram_wdata <= 0;
            bram_we <= 0;
            buf_ready_next <= 0;
            buf_ready <= 0;
        end else begin
            bram_we <= 0;
            buf_ready <= buf_ready_next;
            buf_ready_next <= 0;
            if (rx_valid) begin
                word_buffer <= {rx_data, word_buffer[31:8]};
                total_byte_cnt <= total_byte_cnt + 1;
                if (byte_cnt == 3) begin
                    bram_we <= 1;
                    bram_wdata <= {rx_data, word_buffer[31:8]};
                    bram_waddr <= (total_byte_cnt >> 2);
                    byte_cnt <= 0;
                end else begin
                    byte_cnt <= byte_cnt + 1;
                end
                
                if (total_byte_cnt == 783) begin
                    buf_ready_next <= 1;
                    total_byte_cnt <= 0;
                    byte_cnt <= 0;
                end
            end
        end
    end

endmodule
