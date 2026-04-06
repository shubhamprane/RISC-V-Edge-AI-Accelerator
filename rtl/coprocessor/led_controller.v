`timescale 1ns / 1ps

module led_controller (
    input  wire signed [31:0] max_score,
    output reg  [15:0] led_out
);

    reg [4:0] scaled_count;

    always @(*) begin
        // If the score is negative or zero, confidence is basically zero
        if (max_score <= 0) begin
            scaled_count = 0;
        end else begin
            // Shift the score down to a 0-16 scale. 
            // You may need to adjust "8" based on your actual network's output range.
            scaled_count = max_score[12:8]; 
            
            // Clamp to a maximum of 16 LEDs
            if (scaled_count > 16) begin
                scaled_count = 16;
            end
        end
        
        // Thermometer code generator (16'hFFFF << (16 - scaled_count))
        // e.g., if scaled_count is 3, shifting FFFF by 13 gives 0007 (3 LEDs on)
        led_out = ~(16'hFFFF << scaled_count);
    end

endmodule