`timescale 1ns / 1ps

module seven_seg_controller #(
    parameter REFRESH_COUNT = 100_000 
)(
    input  wire clk,
    input  wire rst,
    input  wire en,
    input  wire [3:0] digit,         
    output reg  [7:0] seg_anode,      
    output reg  [6:0] seg_cathode   
);

    reg [16:0] refresh_counter;
    reg [2:0]  active_digit;

    always @(posedge clk) begin
        if (rst) begin
            refresh_counter <= 0;
            active_digit <= 0;
        end else begin
            if (refresh_counter >= REFRESH_COUNT - 1) begin
                refresh_counter <= 0;
                active_digit <= active_digit + 1;
            end else begin
                refresh_counter <= refresh_counter + 1;
            end
        end
    end

    reg [6:0] pattern;
    always @(*) begin
        case (digit)
            4'd0: pattern = 7'b1000000;
            4'd1: pattern = 7'b1111001;
            4'd2: pattern = 7'b0100100;
            4'd3: pattern = 7'b0110000;
            4'd4: pattern = 7'b0011001;
            4'd5: pattern = 7'b0010010;
            4'd6: pattern = 7'b0000010;
            4'd7: pattern = 7'b1111000;
            4'd8: pattern = 7'b0000000;
            4'd9: pattern = 7'b0010000;
            default: pattern = 7'b1111111;
        endcase
    end

    always @(*) begin
        seg_anode = 8'hFF;
        seg_cathode = 7'b1111111;
        if (en) begin
            case (active_digit)
                3'd0: begin seg_anode = 8'b11111110; seg_cathode = pattern; end
                default: begin seg_anode = 8'hFF; seg_cathode = 7'b1111111; end
            endcase
        end
    end

endmodule
