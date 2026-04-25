`timescale 1ns / 1ps

module top_fpga #(
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096
) (
    input wire clk,  // 100 MHz
    input wire reset,  
    input wire rx,     // UART RX pin
    output wire tx,    // UART TX pin
    output [15:0] led,
    output [7:0] seg_anode,
    output [6:0] seg_cathode
);

    wire [31:0] current_pc;
    wire        exception;

    ////////////////////////////////////////////////////////////
    // Clock divider for slow_clk (10 MHz)
    ////////////////////////////////////////////////////////////
    parameter DIVISOR = 5;
    reg [26:0] clk_cnt;
    reg        slow_clk;

    always @(posedge clk) begin
        if (reset) begin
            clk_cnt  <= 0;
            slow_clk <= 1'b0;
        end else if (clk_cnt == DIVISOR - 1) begin
            clk_cnt  <= 0;
            slow_clk <= ~slow_clk;
        end else begin
            clk_cnt <= clk_cnt + 1;
        end
    end

    ////////////////////////////////////////////////////////////
    // UART Receiver and Input Buffer
    ////////////////////////////////////////////////////////////
    wire [7:0] uart_rx_data;
    wire       uart_rx_valid;
    wire [7:0] buf_waddr;
    wire [31:0] buf_wdata;
    wire       buf_we;
    wire       buf_ready;

    uart_rx #(100_000_000, 115_200) u_uart_rx (
        .clk(clk), .rst(reset), .rx(rx), .rx_data(uart_rx_data), .rx_valid(uart_rx_valid)
    );

    uart_input_buffer u_uart_buf (
        .clk(clk), .rst(reset), .rx_data(uart_rx_data), .rx_valid(uart_rx_valid),
        .bram_waddr(buf_waddr), .bram_wdata(buf_wdata), .bram_we(buf_we), .buf_ready(buf_ready)
    );

    ////////////////////////////////////////////////////////////
    // CDC: buf_ready (100 MHz) to slow_clk (10 MHz)
    ////////////////////////////////////////////////////////////
    reg buf_ready_q;
    always @(posedge clk) buf_ready_q <= buf_ready;

    reg buf_ready_toggle;
    always @(posedge clk or posedge reset) begin
        if (reset) buf_ready_toggle <= 0;
        else if (buf_ready_q) buf_ready_toggle <= ~buf_ready_toggle;
    end

    reg [2:0] buf_ready_sync;
    always @(posedge slow_clk or posedge reset) begin
        if (reset) buf_ready_sync <= 0;
        else buf_ready_sync <= {buf_ready_sync[1:0], buf_ready_toggle};
    end
    wire uart_ready_sync = buf_ready_sync[2] ^ buf_ready_sync[1];

    ////////////////////////////////////////////////////////////
    // MMIO Decoding
    ////////////////////////////////////////////////////////////
    wire [31:0] dmem_read_address;
    wire [31:0] dmem_write_address;
    wire [31:0] dmem_write_data;
    wire [3:0]  dmem_write_byte;
    wire        dmem_read_ready;
    wire        dmem_write_ready;
    wire [31:0] dmem_read_data_temp;
    
    wire is_cop_read  = dmem_read_ready  && (dmem_read_address[31:24] == 8'hC0);
    wire is_cop_write = dmem_write_ready && (dmem_write_address[31:24] == 8'hC0);
    
    wire [31:0] cop_rdata;
    wire [31:0] bram_rdata;
    assign dmem_read_data_temp = is_cop_read ? cop_rdata : bram_rdata;

    wire [31:0] inst_mem_address;
    wire [31:0] inst_mem_read_data;
    wire        inst_mem_is_ready;

    wire [23:0] cpu_cop_addr = is_cop_write ? dmem_write_address[23:0] : dmem_read_address[23:0];
    wire        cpu_cop_re   = dmem_read_ready && (dmem_read_address[31:24] == 8'hC0);

    wire [23:0] log_cop_addr;
    wire        log_cop_re;
    
    wire [23:0] cop_addr = log_cop_re ? log_cop_addr : cpu_cop_addr;
    wire        cop_re   = log_cop_re ? 1'b1 : cpu_cop_re;

    ////////////////////////////////////////////////////////////
    // PIPELINE CPU
    ////////////////////////////////////////////////////////////
    pipe pipe_u (
        .clk(slow_clk), .reset(~reset), .stall(is_cop_read && log_cop_re), .exception(exception), .pc_out(current_pc),
        .inst_mem_address(inst_mem_address), .inst_mem_is_valid(1'b1), .inst_mem_read_data(inst_mem_read_data), .inst_mem_is_ready(inst_mem_is_ready),
        .dmem_read_address(dmem_read_address), .dmem_read_ready(dmem_read_ready), .dmem_read_data_temp(dmem_read_data_temp),
        .dmem_read_valid(1'b1), .dmem_write_address(dmem_write_address), .dmem_write_ready(dmem_write_ready),
        .dmem_write_data(dmem_write_data), .dmem_write_byte(dmem_write_byte), .dmem_write_valid(1'b1)
    );

    instr_mem IMEM (.clk(slow_clk), .pc(inst_mem_address), .instr(inst_mem_read_data));
    data_mem DMEM (.clk(slow_clk), .re(dmem_read_ready && !is_cop_read), .raddr(dmem_read_address), .rdata(bram_rdata),
                   .we(dmem_write_ready && !is_cop_write), .waddr(dmem_write_address), .wdata(dmem_write_data), .wstrb(dmem_write_byte));

    ////////////////////////////////////////////////////////////
    // COPROCESSOR
    ////////////////////////////////////////////////////////////
    wire [3:0]  class_index;
    wire signed [31:0] max_score;
    wire        result_valid;
    
    coprocessor_top cop_u (
        .clk(slow_clk), .rst(reset), .cop_addr(cop_addr), .cop_wdata(dmem_write_data),
        .cop_we(is_cop_write && !log_cop_re), 
        .cop_re(cop_re),
        .uart_ready(uart_ready_sync),
        .in_wclk(clk), .in_we(buf_we), .in_waddr(buf_waddr), .in_wdata(buf_wdata),
        .cop_rdata(cop_rdata), .cop_busy(), .cop_done(),
        .valid_result(result_valid), .class_index(class_index), .max_score(max_score)
    );

    ////////////////////////////////////////////////////////////
    // CDC: result_valid and class_index from slow_clk to clk
    ////////////////////////////////////////////////////////////
    reg [1:0] result_valid_sync;
    reg [3:0] class_index_sync;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            result_valid_sync <= 2'b00;
            class_index_sync  <= 4'd0;
        end else begin
            result_valid_sync <= {result_valid_sync[0], result_valid};
            if (result_valid_sync[0]) class_index_sync <= class_index;
        end
    end
    wire result_valid_clk = result_valid_sync[1];

    ////////////////////////////////////////////////////////////
    // UART LOG SENDER
    ////////////////////////////////////////////////////////////
    wire tx_busy;
    reg  tx_start;
    reg  [7:0] tx_data;
    
    reg [2:0] log_state;
    reg [3:0] log_class_idx;
    reg [1:0] log_byte_idx;
    reg [31:0] log_word;
    
    // Edge detection: only trigger log FSM once per inference
    reg result_valid_prev;
    always @(posedge slow_clk or posedge reset) begin
        if (reset) result_valid_prev <= 0;
        else       result_valid_prev <= result_valid;
    end
    wire result_valid_rise = result_valid && !result_valid_prev;

    assign log_cop_addr = (log_class_idx < 10) ? (24'h000300 + {18'd0, log_class_idx, 2'b00}) :
                         (log_class_idx == 10) ? 24'h000330 : 24'h00032C;
    
    // RE must be high to fetch data from coprocessor registers
    assign log_cop_re   = (log_state == 1 || log_state == 2);
    
    always @(posedge slow_clk or posedge reset) begin
        if (reset) begin
            log_state <= 0;
            log_class_idx <= 0;
            log_byte_idx <= 0;
            tx_start <= 0;
            tx_data <= 0;
        end else begin
            tx_start <= 0;
            case (log_state)
                0: begin
                    // Rising-edge detect: trigger only ONCE per inference
                    if (result_valid_rise) begin
                        log_state <= 5;  // Go to sync header state
                        log_byte_idx <= 0;
                    end
                end
                // State 5: Send 4-byte sync header (0xA5, 0x5A, 0xF0, 0x0F)
                5: begin
                    if (!tx_busy && !tx_start) begin
                        tx_start <= 1;
                        case (log_byte_idx)
                            0: tx_data <= 8'hA5;
                            1: tx_data <= 8'h5A;
                            2: tx_data <= 8'hF0;
                            3: tx_data <= 8'h0F;
                        endcase
                        log_state <= 6;
                    end
                end
                // State 6: Wait for sync byte TX to start, then advance
                6: begin
                    if (tx_busy) begin
                        if (log_byte_idx == 3) begin
                            // Sync header done, start data payload
                            log_class_idx <= 0;
                            log_state <= 1;
                        end else begin
                            log_byte_idx <= log_byte_idx + 1;
                            log_state <= 5;
                        end
                    end
                end
                1: begin
                    // Address is set via log_cop_addr, wait for BRAM/Register latency
                    log_state <= 2;
                end
                2: begin
                    // Data is now stable on cop_rdata
                    log_word <= cop_rdata;
                    log_byte_idx <= 0;
                    log_state <= 3;
                end
                3: begin
                    if (!tx_busy && !tx_start) begin
                        tx_start <= 1;
                        case (log_byte_idx)
                            0: tx_data <= log_word[7:0];
                            1: tx_data <= log_word[15:8];
                            2: tx_data <= log_word[23:16];
                            3: tx_data <= log_word[31:24];
                        endcase
                        log_state <= 4;
                    end
                end
                4: begin
                    if (tx_busy) begin
                        if (log_byte_idx == 3) begin
                            if (log_class_idx == 11) begin // Send 12 words total
                                log_state <= 0; // Done, stay idle
                            end else begin
                                log_class_idx <= log_class_idx + 1;
                                log_state <= 1;
                            end
                        end else begin
                            log_byte_idx <= log_byte_idx + 1;
                            log_state <= 3;
                        end
                    end
                end
            endcase
        end
    end
    
    uart_tx #(10_000_000, 115_200) u_uart_tx (
        .clk(slow_clk), .rst(reset), .tx_data(tx_data), .tx_start(tx_start), .tx(tx), .tx_busy(tx_busy)
    );

    ////////////////////////////////////////////////////////////
    // DISPLAY CONTROLLERS
    ////////////////////////////////////////////////////////////
    led_controller led_u (.confidence_score(max_score), .led_out(led));
    seven_seg_controller sseg_u (.clk(clk), .rst(reset), .en(result_valid_clk && !reset), .digit(class_index_sync),
                                .seg_anode(seg_anode), .seg_cathode(seg_cathode));

endmodule
