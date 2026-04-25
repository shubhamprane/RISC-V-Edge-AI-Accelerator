`timescale 1ns / 1ps

module argmax_unit #(
    parameter N = 10,
    parameter DATA_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    start,
    input  wire [N*DATA_WIDTH-1:0] scores_packed,
    output reg  [3:0]              winner_idx,
    output reg  signed [DATA_WIDTH-1:0] winner_val,
    output reg                     valid
);

    wire signed [DATA_WIDTH-1:0] scores [0:N-1];
    genvar g;
    generate
        for (g=0; g<N; g=g+1) begin : UNPACK
            assign scores[g] = $signed(scores_packed[g*DATA_WIDTH +: DATA_WIDTH]);
        end
    endgenerate

    // Round 1: 5 pairs
    reg signed [DATA_WIDTH-1:0] r1_val [0:4];
    reg [3:0] r1_idx [0:4];
    reg r1_valid;

    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r1_valid <= 0;
            for (i=0; i<5; i=i+1) begin r1_val[i] <= 0; r1_idx[i] <= 0; end
        end else begin
            r1_valid <= start;
            for (i=0; i<5; i=i+1) begin
                if (scores[2*i] >= scores[(2*i+1)]) begin
                    r1_val[i] <= scores[2*i];
                    r1_idx[i] <= 2*i;
                end else begin
                    r1_val[i] <= scores[(2*i+1)];
                    r1_idx[i] <= (2*i+1);
                end
            end
        end
    end

    // Round 2
    reg signed [DATA_WIDTH-1:0] r2_val [0:2];
    reg [3:0] r2_idx [0:2];
    reg r2_valid;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r2_valid <= 0;
            for (i=0; i<3; i=i+1) begin r2_val[i] <= 0; r2_idx[i] <= 0; end
        end else begin
            r2_valid <= r1_valid;
            if (r1_val[0] >= r1_val[1]) begin
                r2_val[0] <= r1_val[0]; r2_idx[0] <= r1_idx[0];
            end else begin
                r2_val[0] <= r1_val[1]; r2_idx[0] <= r1_idx[1];
            end
            if (r1_val[2] >= r1_val[3]) begin
                r2_val[1] <= r1_val[2]; r2_idx[1] <= r1_idx[2];
            end else begin
                r2_val[1] <= r1_val[3]; r2_idx[1] <= r1_idx[3];
            end
            r2_val[2] <= r1_val[4]; r2_idx[2] <= r1_idx[4];
        end
    end

    // Round 3
    reg signed [DATA_WIDTH-1:0] r3_val [0:1];
    reg [3:0] r3_idx [0:1];
    reg r3_valid;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r3_valid <= 0;
            for (i=0; i<2; i=i+1) begin r3_val[i] <= 0; r3_idx[i] <= 0; end
        end else begin
            r3_valid <= r2_valid;
            if (r2_val[0] >= r2_val[1]) begin
                r3_val[0] <= r2_val[0]; r3_idx[0] <= r2_idx[0];
            end else begin
                r3_val[0] <= r2_val[1]; r3_idx[0] <= r2_idx[1];
            end
            r3_val[1] <= r2_val[2]; r3_idx[1] <= r2_idx[2];
        end
    end

    // Final
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid <= 0; winner_idx <= 0; winner_val <= 0;
        end else begin
            valid <= r3_valid;
            if (r3_val[0] >= r3_val[1]) begin
                winner_val <= r3_val[0]; winner_idx <= r3_idx[0];
            end else begin
                winner_val <= r3_val[1]; winner_idx <= r3_idx[1];
            end
        end
    end
endmodule
