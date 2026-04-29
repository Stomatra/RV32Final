`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/16/2025 06:21:44 PM
// Design Name: 
// Module Name: top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module top(
    input  wire i_sys_clk_p         ,
    input  wire i_sys_clk_n         ,
    input  wire i_uart_rx           ,
    output wire o_uart_tx           ,

    output wire [31:0] virtual_led  ,
    output wire [39:0] virtual_seg
);

    wire w_clk_50Mhz, cpu_clk;
    wire w_clk_rst;

    wire [7:0] virtual_key;
    wire [63:0] virtual_sw;
    wire [7:0] virtual_key_cpu;
    wire [63:0] virtual_sw_cpu;
    wire [31:0] student_virtual_led;
    wire [39:0] student_virtual_seg;
    wire [31:0] student_virtual_led_50;
    wire [39:0] student_virtual_seg_50;

    (* ASYNC_REG = "TRUE" *) reg [7:0] virtual_key_cpu_ff1, virtual_key_cpu_ff2;
    (* ASYNC_REG = "TRUE" *) reg [63:0] virtual_sw_cpu_ff1, virtual_sw_cpu_ff2;
    (* ASYNC_REG = "TRUE" *) reg [31:0] student_virtual_led_ff1, student_virtual_led_ff2;
    (* ASYNC_REG = "TRUE" *) reg [39:0] student_virtual_seg_ff1, student_virtual_seg_ff2;

    wire [7:0] rx_data;
    wire rx_ready;
    wire tx_start;
    wire [7:0] tx_data;
    wire tx_busy;

    assign virtual_key_cpu = virtual_key_cpu_ff2;
    assign virtual_sw_cpu = virtual_sw_cpu_ff2;
    assign student_virtual_led_50 = student_virtual_led_ff2;
    assign student_virtual_seg_50 = student_virtual_seg_ff2;

    assign virtual_led = student_virtual_led;
    assign virtual_seg = student_virtual_seg;

    always @(posedge cpu_clk or negedge w_clk_rst) begin
        if (!w_clk_rst) begin
            virtual_key_cpu_ff1 <= 8'd0;
            virtual_key_cpu_ff2 <= 8'd0;
            virtual_sw_cpu_ff1 <= 64'd0;
            virtual_sw_cpu_ff2 <= 64'd0;
        end else begin
            virtual_key_cpu_ff1 <= virtual_key;
            virtual_key_cpu_ff2 <= virtual_key_cpu_ff1;
            virtual_sw_cpu_ff1 <= virtual_sw;
            virtual_sw_cpu_ff2 <= virtual_sw_cpu_ff1;
        end
    end

    always @(posedge w_clk_50Mhz or negedge w_clk_rst) begin
        if (!w_clk_rst) begin
            student_virtual_led_ff1 <= 32'd0;
            student_virtual_led_ff2 <= 32'd0;
            student_virtual_seg_ff1 <= 40'd0;
            student_virtual_seg_ff2 <= 40'd0;
        end else begin
            student_virtual_led_ff1 <= student_virtual_led;
            student_virtual_led_ff2 <= student_virtual_led_ff1;
            student_virtual_seg_ff1 <= student_virtual_seg;
            student_virtual_seg_ff2 <= student_virtual_seg_ff1;
        end
    end

    pll pll_inst(
        .clk_in1_p(i_sys_clk_p),
        .clk_in1_n(i_sys_clk_n),
        .clk_out1(w_clk_50Mhz),
        .clk_out2(cpu_clk),
        .locked(w_clk_rst)
    );

    uart #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(9600)
    ) uart_inst(
        .clk(w_clk_50Mhz),
        .rst_n(w_clk_rst),
        .rx(i_uart_rx),
        .rx_data(rx_data),
        .rx_ready(rx_ready),
        .tx(o_uart_tx),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .tx_busy(tx_busy)
    );

    twin_controller twin_controller_inst(
        .clk(w_clk_50Mhz),
        .rst_n(w_clk_rst),
        .rx_ready(rx_ready),
        .rx_data(rx_data),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .sw(virtual_sw),
        .key(virtual_key),
        .seg(student_virtual_seg_50),
        .led(student_virtual_led_50)
    );

    student_top student_top_inst(
        .w_cpu_clk(cpu_clk),
        .w_clk_50Mhz(w_clk_50Mhz),
        .w_clk_rst(~w_clk_rst),
        .virtual_key(virtual_key_cpu),
        .virtual_sw(virtual_sw_cpu),
        .virtual_led(student_virtual_led),
        .virtual_seg(student_virtual_seg)
    );

endmodule

