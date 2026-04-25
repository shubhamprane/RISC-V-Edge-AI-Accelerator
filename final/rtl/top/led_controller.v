`timescale 1ns / 1ps

module led_controller (
    input  wire signed [31:0] confidence_score,
    output reg  [15:0] led_out
);

    // Heuristic scaling for logit values to LED intensity (0-16 LEDs)
    // Assuming scores range from 0 to some positive max (e.g., 2^16)
    always @(*) begin
        if (confidence_score <= 0) begin
            led_out = 16'h0000;
        end else if (confidence_score >= 32'h0800) begin
            led_out = 16'hFFFF;
        end else begin
            // More sensitive thermometer code based on bits [13:10]
            // Step size = 1024 (2^10)
            case (confidence_score[10:7])
                4'h0: led_out = 16'h0001;
                4'h1: led_out = 16'h0003;
                4'h2: led_out = 16'h0007;
                4'h3: led_out = 16'h000F;
                4'h4: led_out = 16'h001F;
                4'h5: led_out = 16'h003F;
                4'h6: led_out = 16'h007F;
                4'h7: led_out = 16'h00FF;
                4'h8: led_out = 16'h01FF;
                4'h9: led_out = 16'h03FF;
                4'hA: led_out = 16'h07FF;
                4'hB: led_out = 16'h0FFF;
                4'hC: led_out = 16'h1FFF;
                4'hD: led_out = 16'h3FFF;
                4'hE: led_out = 16'h7FFF;
                4'hF: led_out = 16'hFFFF;
                default: led_out = 16'h0001;
            endcase
        end
    end

endmodule
