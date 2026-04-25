`timescale 1ns / 1ps

module tb_uart_full;
    reg clk;
    reg rst;
    reg rx;
    wire [7:0] bram_waddr;
    wire [31:0] bram_wdata;
    wire bram_we;
    wire buf_ready;
    wire [7:0] rx_data_wire;
    wire rx_valid_wire;

    // Use 1,000,000 baud for simulation speed
    uart_rx #(100_000_000, 1_000_000) rx_u (
        .clk(clk), .rst(rst), .rx(rx), .rx_data(rx_data_wire), .rx_valid(rx_valid_wire)
    );

    uart_input_buffer buffer_u (
        .clk(clk), .rst(rst), .rx_data(rx_data_wire), .rx_valid(rx_valid_wire),
        .bram_waddr(bram_waddr), .bram_wdata(bram_wdata), .bram_we(bram_we), .buf_ready(buf_ready)
    );

    always #5 clk = ~clk;

    task send_byte(input [7:0] data);
        integer j;
        begin
            rx = 0; // Start bit
            #(1000); 
            for (j=0; j<8; j=j+1) begin
                rx = data[j];
                #(1000);
            end
            rx = 1; // Stop bit
            #(1000);
        end
    endtask

    integer i;
    initial begin
        clk = 0; rst = 1; rx = 1;
        #100 rst = 0;
        
        $display("Starting UART Full Test...");
        
        fork : main_test
            begin
                $display("Sending 784 bytes at 1M baud...");
                for (i=0; i<784; i=i+1) begin
                    send_byte(i[7:0]);
                end
            end
            begin
                wait(buf_ready);
                $display("PASS: UART Full (buf_ready fired)");
                #100;
                disable main_test;
            end
            begin
                #20000000; // 20ms timeout
                $display("FAIL: UART Full (timeout)");
                disable main_test;
            end
        join
        
        $finish;
    end
endmodule
