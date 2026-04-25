`timescale 1ns / 1ps

module tb_top_uart_to_display;
    reg clk;
    reg reset;
    reg rx;
    wire [15:0] led;
    wire [7:0] seg_anode;
    wire [6:0] seg_cathode;

    top_fpga dut (
        .clk(clk), .reset(reset), .rx(rx),
        .led(led), .seg_anode(seg_anode), .seg_cathode(seg_cathode)
    );
    defparam dut.u_uart_rx.BAUD_RATE = 1_000_000;

    always #5 clk = ~clk;

    localparam BAUD_PERIOD_NS = 960; // 1M baud at 100MHz with 16x oversampling
    task send_byte(input [7:0] data);
        integer j;
        begin
            rx = 0; // Start bit
            #(BAUD_PERIOD_NS);
            for (j=0; j<8; j=j+1) begin
                rx = data[j];
                #(BAUD_PERIOD_NS);
            end
            rx = 1; // Stop bit
            #(BAUD_PERIOD_NS);
        end
    endtask

    integer i;
    initial begin
        clk = 0; reset = 1; rx = 1;
        #100 reset = 0;
        
        $display("Sending 784 bytes via UART...");
        for (i=0; i<784; i=i+1) begin
            send_byte(8'h01);
        end
        
        $display("UART Transmission complete. Waiting for inference...");
        
        fork : inference_wait
            begin
                wait(dut.result_valid);
                $display("Inference Complete!");
                $display("Class Index: %d", dut.class_index);
                $display("Max Score: %d", dut.max_score);
                // Wait for display to become active (cycle through digits)
                for (i=0; i<1000000; i=i+1) begin
                    @(posedge clk);
                    if (seg_anode !== 8'hFF) break;
                end
                if (seg_anode !== 8'hFF)
                    $display("PASS: Display Active (anode=%h)", seg_anode);
                else
                    $display("FAIL: Display still inactive after 10ms");
                disable inference_wait;
            end
            begin
                #200_000_000; // 200ms timeout
                $display("FAIL: Timeout waiting for inference");
                disable inference_wait;
            end
        join
        
        $finish;
    end
endmodule
