`timescale 1ns / 1ps

module led_const_test(
    input  wire        i_sys_clk_p,
    input  wire        i_sys_clk_n,
    input  wire        i_uart_rx,
    output wire        o_uart_tx,
    output wire [31:0] virtual_led,
    output wire [39:0] virtual_seg
);
    wire sys_clk;
    wire [31:0] seg_value;
    wire [6:0] seg1;
    wire [6:0] seg2;
    wire [6:0] seg3;
    wire [6:0] seg4;
    wire [7:0] ans;

    IBUFDS sys_clk_ibuf (
        .I (i_sys_clk_p),
        .IB(i_sys_clk_n),
        .O (sys_clk)
    );

    assign virtual_led = 32'h03030303;
    assign seg_value = 32'h12345678;
    assign o_uart_tx = 1'b1;

    display_seg seg_const (
        .clk (sys_clk),
        .rst (1'b0),
        .s   (seg_value),
        .seg1(seg1),
        .seg2(seg2),
        .seg3(seg3),
        .seg4(seg4),
        .ans (ans)
    );

    assign virtual_seg[6:0]   = seg1;
    assign virtual_seg[7]     = 1'b0;
    assign virtual_seg[9:8]   = ans[1:0];
    assign virtual_seg[16:10] = seg2;
    assign virtual_seg[17]    = 1'b0;
    assign virtual_seg[19:18] = ans[3:2];
    assign virtual_seg[26:20] = seg3;
    assign virtual_seg[27]    = 1'b0;
    assign virtual_seg[29:28] = ans[5:4];
    assign virtual_seg[36:30] = seg4;
    assign virtual_seg[37]    = 1'b0;
    assign virtual_seg[39:38] = ans[7:6];
endmodule
