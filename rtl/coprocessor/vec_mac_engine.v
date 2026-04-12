`timescale 1ns / 1ps

module vec_mac_engine #(
    parameter LANES = 4
) (
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire [8*LANES-1:0] vec_a,     
    input  wire [8*LANES-1:0] vec_b,     
    input  wire signed [31:0] bias,      
    input  wire [15:0] n_elements,       
    input  wire        relu_en,

    output reg  signed [31:0] result,
    output reg  done,
    output reg  busy
);

    integer j; // Declare loop variable at top

    // 1. Unpacking
    wire signed [7:0] a_unpacked [0:LANES-1];
    wire signed [7:0] b_unpacked [0:LANES-1];

    genvar i;
    generate
        for (i = 0; i < LANES; i = i + 1) begin : UNPACK_BLOCK
            assign a_unpacked[i] = $signed(vec_a[(i*8) +: 8]);
            assign b_unpacked[i] = $signed(vec_b[(i*8) +: 8]);
        end
    endgenerate

    // 2. PIPELINED MULTIPLIERS (Stage 1)
    reg signed [15:0] products [0:LANES-1];
    always @(posedge clk) begin
        if (rst) begin
            for (j = 0; j < LANES; j = j + 1) products[j] <= 0;
        end else begin
            for (j = 0; j < LANES; j = j + 1) begin
                products[j] <= a_unpacked[j] * b_unpacked[j];
            end
        end
    end

    // 3. PIPELINED ACCUMULATOR (Stage 2)
    reg signed [31:0] sum_of_products_reg;
    always @(posedge clk) begin
        if (rst) begin
            sum_of_products_reg <= 0;
        end else begin
            sum_of_products_reg <= products[0] + products[1] + products[2] + products[3];
        end
    end

    // 4. FSM
    localparam S_IDLE      = 3'b000;
    localparam S_PRELOAD1  = 3'b001; 
    localparam S_PRELOAD2  = 3'b010; 
    localparam S_COMPUTE   = 3'b011;
    localparam S_BIAS_RELU = 3'b100;
    localparam S_DONE      = 3'b101;

    reg [2:0] state;
    reg signed [31:0] acc;
    reg [15:0] count;
    
    // final_biased_val is purely combinatorial within the state transition
    wire signed [31:0] final_biased_val = acc + bias;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; acc <= 0; count <= 0; result <= 0; done <= 0; busy <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        busy <= 1; acc <= 0; count <= 0; state <= S_PRELOAD1;
                    end
                end
                S_PRELOAD1: state <= S_PRELOAD2;
                S_PRELOAD2: state <= S_COMPUTE;
                S_COMPUTE: begin
                    acc   <= acc + sum_of_products_reg;
                    count <= count + LANES;
                    if (count >= n_elements) state <= S_BIAS_RELU;
                end
                S_BIAS_RELU: begin
                    if (relu_en && final_biased_val < 0) result <= 0;
                    else result <= final_biased_val;
                    state <= S_DONE;
                end
                S_DONE: begin
                    done <= 1; busy <= 0; state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
