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


module top #(
    parameter integer CPU_CLK_FREQ_HZ = 260_000_000,
    parameter integer UART_BAUD_RATE  = 115200
) (
    input  wire i_sys_clk_p         ,
    input  wire i_sys_clk_n         ,
    input  wire i_uart_rx           ,
    output wire o_uart_tx           ,

    output wire [31:0] virtual_led  ,
    output wire [39:0] virtual_seg   ,
    output logic       hdmi_tx_clk_p ,
    output logic       hdmi_tx_clk_n ,
    output logic [2:0] hdmi_tx_data_p,
    output logic [2:0] hdmi_tx_data_n
);
	// top 是整板顶层：
	// - 处理差分系统时钟输入
	// - 生成 50MHz 外设时钟和 CPU 时钟
	// - 处理 UART twin 通道与 student_top 之间的跨时钟同步

    wire w_clk_50Mhz, cpu_clk;
    wire w_clk_rst;

    wire [7:0] virtual_key;
    wire [63:0] virtual_sw;
    wire [7:0] virtual_key_cpu;
    wire [63:0] virtual_sw_cpu;
    wire [31:0] student_virtual_led;
    wire [39:0] student_virtual_seg;
    wire [31:0] student_virtual_led_src;
    wire [39:0] student_virtual_seg_src;
    wire [31:0] student_virtual_led_50;
    wire [39:0] student_virtual_seg_50;

	// 这些双触发同步器负责两个方向的跨时钟域采样：
	// 1. twin_controller(50MHz) -> CPU 域的按键/拨码输入
	// 2. CPU 域 -> twin_controller(50MHz) 的显示输出
    (* ASYNC_REG = "TRUE" *) reg [7:0] virtual_key_cpu_ff1, virtual_key_cpu_ff2;
    (* ASYNC_REG = "TRUE" *) reg [63:0] virtual_sw_cpu_ff1, virtual_sw_cpu_ff2;
    (* ASYNC_REG = "TRUE" *) reg [31:0] student_virtual_led_ff1, student_virtual_led_ff2;
    (* ASYNC_REG = "TRUE" *) reg [39:0] student_virtual_seg_ff1, student_virtual_seg_ff2;

    wire [7:0] rx_data;
    wire rx_ready;
    wire tx_start;
    wire [7:0] tx_data;
    wire tx_busy;
    wire twin_uart_tx;
    wire cpu_uart_tx;

    // Both UART TX sources idle high. This preserves the existing twin UART
    // when the CPU MMIO UART is idle, while still allowing CPU printf output.
    assign o_uart_tx = twin_uart_tx & cpu_uart_tx;

	// PLL 产生 50MHz 和 CPU 主频，同时 locked 也被用作系统复位释放条件。
    pll pll_inst(
        .clk_in1_p(i_sys_clk_p),
        .clk_in1_n(i_sys_clk_n),
        .clk_out1(w_clk_50Mhz),
        .clk_out2(cpu_clk),
        .locked(w_clk_rst)
    );

`ifdef ENABLE_HDMI_DEMO
    wire hdmi_pixel_clk;
    wire hdmi_pixel_clk_5x;
    wire hdmi_clk_locked;
    wire hdmi_rst;
    wire hdmi_tx_clk_p_w;
    wire hdmi_tx_clk_n_w;
    wire [2:0] hdmi_tx_data_p_w;
    wire [2:0] hdmi_tx_data_n_w;

    assign hdmi_rst = ~hdmi_clk_locked;
    assign hdmi_tx_clk_p = hdmi_tx_clk_p_w;
    assign hdmi_tx_clk_n = hdmi_tx_clk_n_w;
    assign hdmi_tx_data_p = hdmi_tx_data_p_w;
    assign hdmi_tx_data_n = hdmi_tx_data_n_w;

    hdmi_clock_gen hdmi_clock_gen_inst (
        .clk_in         (w_clk_50Mhz),
        .rst            (~w_clk_rst),
        .pixel_clk      (hdmi_pixel_clk),
        .pixel_clk_5x   (hdmi_pixel_clk_5x),
        .locked         (hdmi_clk_locked)
    );

    hdmi_demo hdmi_demo_inst (
        .pixel_clk          (hdmi_pixel_clk),
        .pixel_clk_5x       (hdmi_pixel_clk_5x),
        .rst                (hdmi_rst),
        .hdmi_tx_clk_p      (hdmi_tx_clk_p_w),
        .hdmi_tx_clk_n      (hdmi_tx_clk_n_w),
        .hdmi_tx_data_p     (hdmi_tx_data_p_w),
        .hdmi_tx_data_n     (hdmi_tx_data_n_w)
    );
`else
    assign hdmi_tx_clk_p = 1'b0;
    assign hdmi_tx_clk_n = 1'b1;
    assign hdmi_tx_data_p = 3'b000;
    assign hdmi_tx_data_n = 3'b111;
`endif

`ifdef LED_WALK_TEST
    localparam integer LED_WALK_TICKS = 50_000_000;
    localparam [25:0] LED_WALK_LAST = LED_WALK_TICKS - 1;

    reg [25:0] led_walk_counter;
    reg [4:0]  led_walk_index;
    reg [31:0] led_walk_value;
    reg [3:0]  led_walk_tens;
    reg [3:0]  led_walk_ones;
    wire [31:0] led_walk_seg_word;
    wire [6:0]  led_walk_seg1;
    wire [6:0]  led_walk_seg2;
    wire [6:0]  led_walk_seg3;
    wire [6:0]  led_walk_seg4;
    wire [7:0]  led_walk_ans;

    assign student_virtual_led_src = led_walk_value;
    assign cpu_uart_tx = 1'b1;
    assign led_walk_seg_word = {24'd0, led_walk_tens, led_walk_ones};
    assign student_virtual_seg_src = {
        led_walk_ans[7:6], 1'b0, led_walk_seg4,
        led_walk_ans[5:4], 1'b0, led_walk_seg3,
        led_walk_ans[3:2], 1'b0, led_walk_seg2,
        led_walk_ans[1:0], 1'b0, led_walk_seg1
    };

    display_seg led_walk_seg_driver (
        .clk    (w_clk_50Mhz),
        .rst    (~w_clk_rst),
        .s      (led_walk_seg_word),
        .seg1   (led_walk_seg1),
        .seg2   (led_walk_seg2),
        .seg3   (led_walk_seg3),
        .seg4   (led_walk_seg4),
        .ans    (led_walk_ans)
    );

    always @(*) begin
        led_walk_value = 32'h0000_0001 << led_walk_index;
        led_walk_tens = 4'd0;
        led_walk_ones = led_walk_index[3:0];
        if (led_walk_index >= 5'd30) begin
            led_walk_tens = 4'd3;
            led_walk_ones = led_walk_index - 5'd30;
        end else if (led_walk_index >= 5'd20) begin
            led_walk_tens = 4'd2;
            led_walk_ones = led_walk_index - 5'd20;
        end else if (led_walk_index >= 5'd10) begin
            led_walk_tens = 4'd1;
            led_walk_ones = led_walk_index - 5'd10;
        end
    end

    always @(posedge w_clk_50Mhz or negedge w_clk_rst) begin
        if (!w_clk_rst) begin
            led_walk_counter <= 26'd0;
            led_walk_index <= 5'd0;
        end else if (led_walk_counter == LED_WALK_LAST) begin
            led_walk_counter <= 26'd0;
            led_walk_index <= led_walk_index + 5'd1;
        end else begin
            led_walk_counter <= led_walk_counter + 26'd1;
        end
    end
`endif

    assign virtual_key_cpu = virtual_key_cpu_ff2;
    assign virtual_sw_cpu = virtual_sw_cpu_ff2;
    assign student_virtual_led = student_virtual_led_src;
    assign student_virtual_seg = student_virtual_seg_src;
    assign student_virtual_led_50 = student_virtual_led_ff2;
    assign student_virtual_seg_50 = student_virtual_seg_ff2;

    assign virtual_led = student_virtual_led;
    assign virtual_seg = student_virtual_seg;

	// 将 UART/twin 侧的输入同步到 CPU 时钟域。
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

	// 将 CPU 侧 LED/数码管状态同步回 50MHz twin/UART 域。
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

	// UART 只运行在 50MHz 域，供 twin_controller 做上位机交互。
    uart #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(9600)
    ) uart_inst(
        .clk(w_clk_50Mhz),
        .rst_n(w_clk_rst),
        .rx(i_uart_rx),
        .rx_data(rx_data),
        .rx_ready(rx_ready),
        .tx(twin_uart_tx),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .tx_busy(tx_busy)
    );

	// twin_controller 负责把 UART 协议翻译成开关/按键输入与状态回读。
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

	// student_top 是板上学生设计主体。
`ifndef LED_WALK_TEST
    student_top #(
        .CPU_CLK_FREQ_HZ    (CPU_CLK_FREQ_HZ),
        .UART_BAUD_RATE     (UART_BAUD_RATE)
    ) student_top_inst(
        .w_cpu_clk(cpu_clk),
        .w_clk_50Mhz(w_clk_50Mhz),
        .w_clk_rst(~w_clk_rst),
        .virtual_key(virtual_key_cpu),
        .virtual_sw(virtual_sw_cpu),
        .uart_rx_i(i_uart_rx),
        .virtual_led(student_virtual_led_src),
        .virtual_seg(student_virtual_seg_src),
        .uart_tx_o(cpu_uart_tx)
    );
`endif
endmodule
