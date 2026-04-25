`timescale 1ns/1ps
module tb_uart;
    reg clk, rst, rx;
    wire [7:0] rx_data;
    wire rx_valid;

    uart_rx #(100_000_000, 115_200) dut (
        .clk(clk), .rst(rst), .rx(rx), .rx_data(rx_data), .rx_valid(rx_valid)
    );

    always #5 clk = ~clk;

    task send_byte(input [7:0] data);
        integer i;
        begin
            rx = 0; #8680; // Start bit (approx 8680ns for 115200)
            for (i=0; i<8; i=i+1) begin
                rx = data[i]; #8680;
            end
            rx = 1; #8680; // Stop bit
        end
    endtask

    initial begin
        clk = 0; rst = 1; rx = 1;
        #100 rst = 0;
        
        #1000 send_byte(8'hA5);
        wait(rx_valid); #10;
        if (rx_data == 8'hA5) $display("TB_UART: Byte 0xA5 PASS");
        else $display("TB_UART: Byte 0xA5 FAIL (Got 0x%h)", rx_data);

        #1000 send_byte(8'h3C);
        wait(rx_valid); #10;
        if (rx_data == 8'h3C) $display("TB_UART: Byte 0x3C PASS");
        else $display("TB_UART: Byte 0x3C FAIL (Got 0x%h)", rx_data);

        #50000 $display("TB_UART: COMPLETE");
        $finish;
    end
endmodule
