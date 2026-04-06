`timescale 1ns / 1ps

module top_fpga #(
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096
) (
    input  wire clk,           // 100 MHz board clock
    input  wire reset,         // Active-high reset
    
    // Physical IO
    output wire [15:0] led,           // 16 LEDs for Confidence Bar
    input  wire uart_rxd,             // UART serial in from PC
    output wire [6:0] seg_cathode,    // 7-segment display cathodes
    output wire [3:0] seg_anode       // 7-segment display anodes
);

    wire sys_clk = clk; // Master clock for the entire SoC

    // =========================================================================
    // 1. Pipeline & Memory Wires
    // =========================================================================
    wire [31:0] current_pc;
    wire        exception;

    wire [31:0] inst_mem_address;
    wire        inst_mem_is_valid = 1'b1;
    wire [31:0] inst_mem_read_data;
    wire        inst_mem_is_ready;

    wire [31:0] dmem_read_address;
    wire        dmem_read_ready;
    wire [31:0] dmem_read_data_to_pipe; // Muxed output back to CPU
    wire        dmem_read_valid = 1'b1;
    
    wire [31:0] dmem_write_address;
    wire        dmem_write_ready;
    wire [31:0] dmem_write_data;
    wire [ 3:0] dmem_write_byte;
    wire        dmem_write_valid = 1'b1;

    // =========================================================================
    // 2. MMIO Address Decoder (The "Traffic Cop")
    // =========================================================================
    // Anything starting with 0xC0 (e.g., 0xC000_0000) belongs to the Coprocessor.
    // Everything else goes to standard Data Memory (BRAM).
    
    wire is_cop_req   = (dmem_write_address[31:24] == 8'hC0) || (dmem_read_address[31:24] == 8'hC0);
    wire is_cop_write = dmem_write_ready && is_cop_req;
    wire is_cop_read  = dmem_read_ready  && is_cop_req;

    // Gate the standard memory so it doesn't activate during Coprocessor accesses
    wire dmem_we_gated = dmem_write_ready && !is_cop_req;
    wire dmem_re_gated = dmem_read_ready  && !is_cop_req;

    wire [31:0] cop_rdata;
    wire [31:0] bram_rdata;

    // Mux: If CPU reads 0xC0..., give it Coprocessor data. Otherwise, BRAM data.
    assign dmem_read_data_to_pipe = is_cop_read ? cop_rdata : bram_rdata;

    // =========================================================================
    // 3. Coprocessor & Pipeline Stall Signals
    // =========================================================================
    wire cop_busy;
    wire cop_done;
    
    // Freeze the CPU pipeline when the MAC engine is calculating
    wire stall_pipeline = cop_busy; 

    // =========================================================================
    // 4. UART & Display Wires
    // =========================================================================
    wire [7:0] uart_byte;
    wire       uart_byte_valid;
    wire [3:0] class_index;
    wire signed [31:0] max_score;

    // =========================================================================
    // 5. Module Instantiations
    // =========================================================================

    // --- RISC-V Pipeline ---
    pipe pipe_u (
        .clk(sys_clk),
        .reset(~reset), // Assuming pipe expects active-low internally based on your code
        .stall(stall_pipeline), // INJECT COPROCESSOR STALL HERE
        .exception(exception),
        .pc_out(current_pc),
        
        .inst_mem_address(inst_mem_address),
        .inst_mem_is_valid(inst_mem_is_valid),
        .inst_mem_read_data(inst_mem_read_data),
        .inst_mem_is_ready(inst_mem_is_ready),

        .dmem_read_address(dmem_read_address),
        .dmem_read_ready(dmem_read_ready),
        .dmem_read_data_temp(dmem_read_data_to_pipe), // Connect to MUX output
        .dmem_read_valid(dmem_read_valid),
        
        .dmem_write_address(dmem_write_address),
        .dmem_write_ready(dmem_write_ready),
        .dmem_write_data(dmem_write_data),
        .dmem_write_byte(dmem_write_byte),
        .dmem_write_valid(dmem_write_valid)
    );

    // --- Standard Instruction Memory ---
    instr_mem IMEM (
        .clk(sys_clk),
        .pc(inst_mem_address),
        .instr(inst_mem_read_data)
    );

    // --- Standard Data Memory (Gated by Decoder) ---
    data_mem DMEM (
        .clk(sys_clk),
        .re(dmem_re_gated),
        .raddr(dmem_read_address),
        .rdata(bram_rdata), // Connect to MUX input
        .we(dmem_we_gated),
        .waddr(dmem_write_address),
        .wdata(dmem_write_data),
        .wstrb(dmem_write_byte)
    );

    // --- Neural Network Coprocessor (Master CSR Hub) ---
    coprocessor_top cop_u (
        .clk(sys_clk),
        .rst(reset),
        
        // MMIO Bus
        .cop_addr(is_cop_write ? dmem_write_address[23:0] : dmem_read_address[23:0]),
        .cop_wdata(dmem_write_data),
        .cop_we(is_cop_write),
        .cop_re(is_cop_read),
        .cop_rdata(cop_rdata),
        .cop_busy(cop_busy),
        .cop_done(cop_done),
        
        // UART Input BRAM Writer (Bypasses CPU)
        .uart_byte(uart_byte),
        .uart_byte_valid(uart_byte_valid),
        
        // Outputs to Displays
        .class_index(class_index),
        .max_score(max_score) 
    );

    // --- UART Receiver ---
    uart_rx #(.CLKS_PER_BIT(868)) uart_rx_u (
        .clk(sys_clk),
        .rst(reset),
        .rxd(uart_rxd),
        .byte_out(uart_byte),
        .byte_valid(uart_byte_valid),
        .frame_error()
    );

    // --- Hardware Display Controllers ---
    seven_seg_controller #(.REFRESH_COUNT(100_000)) seg_u (
        .clk(sys_clk),
        .rst(reset),
        .digit(class_index),
        .seg_cathode(seg_cathode),
        .seg_anode(seg_anode)
    );

    led_controller led_u (
        .max_score(max_score),
        .led_out(led)
    );

endmodule
