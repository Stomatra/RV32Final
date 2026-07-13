`timescale 1ns / 1ps

module top_cpu_hdmi_uart_rx_echo_status (
    input  wire        i_sys_clk_p,
    input  wire        i_sys_clk_n,
    input  wire        i_uart_rx,
    output wire        o_uart_tx,
    input  wire        hdmi_hpd,
    output wire        hdmi_tx_clk_p,
    output wire        hdmi_tx_clk_n,
    output wire [2:0]  hdmi_tx_data_p,
    output wire [2:0]  hdmi_tx_data_n,
    output wire [31:0] virtual_led,
    output wire [39:0] virtual_seg
);
    localparam integer CPU_CLK_FREQ_HZ = 200_000_000;
    localparam integer CPU_UART_BAUD_RATE = 115200;

    wire sys_clk;
    wire clk_50m;
    wire cpu_clk;
    wire cpu_clk_locked;
    wire pixel_clk;
    wire serial_clk;
    wire hdmi_clk_locked;
    wire cpu_reset;
    wire cpu_uart_tx;
    wire [11:0] inst_addr;
    wire [31:0] instruction;
    wire [31:0] perip_addr;
    wire [31:0] perip_wdata;
    wire [31:0] perip_rdata;
    wire        perip_wen;
    wire [1:0]  perip_mask;
    wire [31:0] cpu_led_value;
    wire [39:0] cpu_seg_scan_value;
    wire [31:0] cpu_seg_value;
    wire        uart_tx_ready;
    wire        uart_rx_valid;
    wire        uart_rx_overrun;
    wire [7:0]  uart_rx_data;

    logic [7:0] reset_shift;
    wire hdmi_rst;

    (* ASYNC_REG = "TRUE" *) logic [31:0] led_pixel_ff1, led_pixel_ff2;
    (* ASYNC_REG = "TRUE" *) logic [31:0] seg_pixel_ff1, seg_pixel_ff2;
    (* ASYNC_REG = "TRUE" *) logic [7:0]  rx_data_pixel_ff1, rx_data_pixel_ff2;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  rx_valid_pixel_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  tx_ready_pixel_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  hpd_pixel_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  lock_pixel_sync;

    assign o_uart_tx = cpu_uart_tx;
    assign virtual_led = cpu_led_value;
    assign virtual_seg = cpu_seg_scan_value;
    assign cpu_reset = ~cpu_clk_locked;

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

    hdmi_clock_gen_720p_ref #(
        .CLKIN1_PERIOD_NS (5.000),
        .CLKFBOUT_MULT_F  (37.125),
        .DIVCLK_DIVIDE    (10),
        .CLKOUT0_DIVIDE_F (10.000),
        .CLKOUT1_DIVIDE   (2)
    ) hdmi_clock_gen_inst (
        .clk_in     (sys_clk),
        .rst        (1'b0),
        .pixel_clk  (pixel_clk),
        .serial_clk (serial_clk),
        .locked     (hdmi_clk_locked)
    );

    always_ff @(posedge pixel_clk or negedge hdmi_clk_locked) begin
        if (!hdmi_clk_locked) begin
            reset_shift <= 8'h00;
        end else begin
            reset_shift <= {reset_shift[6:0], 1'b1};
        end
    end

    assign hdmi_rst = ~reset_shift[7];

    myCPU Core_cpu (
        .cpu_rst     (cpu_reset),
        .cpu_clk     (cpu_clk),
        .irom_addr   (inst_addr),
        .irom_data   (instruction),
        .perip_addr  (perip_addr),
        .perip_wen   (perip_wen),
        .perip_mask  (perip_mask),
        .perip_wdata (perip_wdata),
        .perip_rdata (perip_rdata)
    );

    IROM Mem_IROM (
        .a   (inst_addr),
        .spo (instruction)
    );

    perip_bridge #(
        .CLK_FREQ_HZ    (CPU_CLK_FREQ_HZ),
        .UART_BAUD_RATE (CPU_UART_BAUD_RATE)
    ) bridge_inst (
        .clk                      (cpu_clk),
        .cnt_clk                  (clk_50m),
        .rst                      (cpu_reset),
        .perip_addr               (perip_addr),
        .perip_wdata              (perip_wdata),
        .perip_wen                (perip_wen),
        .perip_mask               (perip_mask),
        .perip_rdata              (perip_rdata),
        .virtual_sw_input         (64'h0),
        .virtual_key_input        (8'h00),
        .uart_rx_i                (i_uart_rx),
        .virtual_seg_output       (cpu_seg_scan_value),
        .virtual_seg_value_output (cpu_seg_value),
        .virtual_led_output       (cpu_led_value),
        .uart_tx_o                (cpu_uart_tx),
        .uart_tx_ready_o          (uart_tx_ready),
        .uart_rx_valid_o          (uart_rx_valid),
        .uart_rx_overrun_o        (uart_rx_overrun),
        .uart_rx_data_o           (uart_rx_data)
    );

    always_ff @(posedge pixel_clk or posedge hdmi_rst) begin
        if (hdmi_rst) begin
            led_pixel_ff1 <= 32'd0;
            led_pixel_ff2 <= 32'd0;
            seg_pixel_ff1 <= 32'd0;
            seg_pixel_ff2 <= 32'd0;
            rx_data_pixel_ff1 <= 8'h00;
            rx_data_pixel_ff2 <= 8'h00;
            rx_valid_pixel_sync <= 2'b00;
            tx_ready_pixel_sync <= 2'b00;
            hpd_pixel_sync <= 2'b00;
            lock_pixel_sync <= 2'b00;
        end else begin
            led_pixel_ff1 <= cpu_led_value;
            led_pixel_ff2 <= led_pixel_ff1;
            seg_pixel_ff1 <= cpu_seg_value;
            seg_pixel_ff2 <= seg_pixel_ff1;
            rx_data_pixel_ff1 <= uart_rx_data;
            rx_data_pixel_ff2 <= rx_data_pixel_ff1;
            rx_valid_pixel_sync <= {rx_valid_pixel_sync[0], uart_rx_valid};
            tx_ready_pixel_sync <= {tx_ready_pixel_sync[0], uart_tx_ready};
            hpd_pixel_sync <= {hpd_pixel_sync[0], hdmi_hpd};
            lock_pixel_sync <= {lock_pixel_sync[0], hdmi_clk_locked};
        end
    end

    hdmi_uart_status_panel hdmi_uart_status_panel_inst (
        .pixel_clk      (pixel_clk),
        .serial_clk     (serial_clk),
        .rst            (hdmi_rst),
        .led_value      (led_pixel_ff2),
        .seg_value      (seg_pixel_ff2),
        .rx_valid       (rx_valid_pixel_sync[1]),
        .rx_data        (rx_data_pixel_ff2),
        .tx_ready       (tx_ready_pixel_sync[1]),
        .hpd            (hpd_pixel_sync[1]),
        .locked         (lock_pixel_sync[1]),
        .hdmi_tx_clk_p  (hdmi_tx_clk_p),
        .hdmi_tx_clk_n  (hdmi_tx_clk_n),
        .hdmi_tx_data_p (hdmi_tx_data_p),
        .hdmi_tx_data_n (hdmi_tx_data_n)
    );

endmodule
