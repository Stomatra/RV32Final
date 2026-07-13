`timescale 1ns / 1ps

module top_uart_rx_echo_test (
    input  wire        i_sys_clk_p,
    input  wire        i_sys_clk_n,
    input  wire        i_uart_rx,
    output wire        o_uart_tx,
    output wire [31:0] virtual_led,
    output wire [39:0] virtual_seg
);
    localparam integer CPU_CLK_FREQ_HZ = 200_000_000;
    localparam integer CPU_UART_BAUD_RATE = 115200;

    wire sys_clk;
    wire clk_50m;
    wire cpu_clk;
    wire cpu_clk_locked;
    wire [31:0] cpu_seg_value;

    IBUFDS ibufds_sys_clk (
        .I  (i_sys_clk_p),
        .IB (i_sys_clk_n),
        .O  (sys_clk)
    );

    cpu_clock_gen_status cpu_clock_gen_inst (
        .clk_in  (sys_clk),
        .rst     (1'b0),
        .clk_50m (clk_50m),
        .cpu_clk (cpu_clk),
        .locked  (cpu_clk_locked)
    );

    student_top #(
        .CPU_CLK_FREQ_HZ (CPU_CLK_FREQ_HZ),
        .UART_BAUD_RATE  (CPU_UART_BAUD_RATE)
    ) student_top_inst (
        .w_cpu_clk         (cpu_clk),
        .w_clk_50Mhz       (clk_50m),
        .w_clk_rst         (~cpu_clk_locked),
        .virtual_key       (8'h00),
        .virtual_sw        (64'h0),
        .uart_rx_i         (i_uart_rx),
        .virtual_led       (virtual_led),
        .virtual_seg       (virtual_seg),
        .virtual_seg_value (cpu_seg_value),
        .uart_tx_o         (o_uart_tx)
    );

endmodule
