`timescale 1ns / 1ps

module argmax_tree (
    // Flattened array of 10 INT32 scores (0 to 9)
    // Verilog-2001 doesn't allow 2D array ports easily, so we pack them into 320 bits
    input  wire [319:0] packed_scores, 
    
    output reg  [3:0]  class_index,
    output reg  signed [31:0] max_score
);

    wire signed [31:0] s [0:9];
    
    // Unpack the scores
    genvar i;
    generate
        for (i = 0; i < 10; i = i + 1) begin : UNPACK
            assign s[i] = $signed(packed_scores[(i*32) +: 32]);
        end
    endgenerate

    // Tournament Variables
    reg signed [31:0] w1_01, w1_23, w1_45, w1_67, w1_89;
    reg [3:0] i1_01, i1_23, i1_45, i1_67, i1_89;

    reg signed [31:0] w2_03, w2_47;
    reg [3:0] i2_03, i2_47;

    reg signed [31:0] w3_07;
    reg [3:0] i3_07;

    always @(*) begin
        // --- LEVEL 1 ---
        if (s[0] > s[1]) begin w1_01 = s[0]; i1_01 = 4'd0; end else begin w1_01 = s[1]; i1_01 = 4'd1; end
        if (s[2] > s[3]) begin w1_23 = s[2]; i1_23 = 4'd2; end else begin w1_23 = s[3]; i1_23 = 4'd3; end
        if (s[4] > s[5]) begin w1_45 = s[4]; i1_45 = 4'd4; end else begin w1_45 = s[5]; i1_45 = 4'd5; end
        if (s[6] > s[7]) begin w1_67 = s[6]; i1_67 = 4'd6; end else begin w1_67 = s[7]; i1_67 = 4'd7; end
        if (s[8] > s[9]) begin w1_89 = s[8]; i1_89 = 4'd8; end else begin w1_89 = s[9]; i1_89 = 4'd9; end

        // --- LEVEL 2 ---
        if (w1_01 > w1_23) begin w2_03 = w1_01; i2_03 = i1_01; end else begin w2_03 = w1_23; i2_03 = i1_23; end
        if (w1_45 > w1_67) begin w2_47 = w1_45; i2_47 = i1_45; end else begin w2_47 = w1_67; i2_47 = i1_67; end

        // --- LEVEL 3 ---
        if (w2_03 > w2_47) begin w3_07 = w2_03; i3_07 = i2_03; end else begin w3_07 = w2_47; i3_07 = i2_47; end

        // --- LEVEL 4 (Final) ---
        if (w3_07 > w1_89) begin 
            max_score = w3_07; 
            class_index = i3_07; 
        end else begin 
            max_score = w1_89; 
            class_index = i1_89; 
        end
    end

endmodule