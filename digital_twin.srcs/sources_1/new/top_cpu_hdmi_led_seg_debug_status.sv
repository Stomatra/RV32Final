`timescale 1ns / 1ps

module top_cpu_hdmi_led_seg_debug_status (
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
    localparam logic [31:0] SEG_ADDR = 32'h8020_0020;
    localparam logic [31:0] LED_ADDR = 32'h8020_0040;

    wire sys_clk;
    wire clk_50m;
    wire cpu_clk;
    wire cpu_clk_locked;
    wire pixel_clk;
    wire serial_clk;
    wire hdmi_clk_locked;
    wire cpu_uart_tx;
    wire twin_uart_tx;
    wire tx_start;
    wire [7:0] tx_data;
    wire tx_busy;
    wire [7:0] rx_data;
    wire rx_ready;
    wire [7:0] virtual_key_50;
    wire [63:0] virtual_sw_50;
    wire [7:0] virtual_key_cpu;
    wire [63:0] virtual_sw_cpu;
    wire [31:0] cpu_led_value;
    wire [39:0] cpu_seg_scan_value;
    wire [31:0] cpu_seg_value;
    wire [31:0] cpu_led_50;
    wire [39:0] cpu_seg_scan_50;
    wire [11:0] inst_addr;
    wire [31:0] instruction;
    wire [31:0] perip_addr;
    wire [31:0] perip_wdata;
    wire [31:0] perip_rdata;
    wire perip_wen;
    wire [1:0] perip_mask;

    logic [7:0] reset_shift;
    wire hdmi_rst;
    wire cpu_reset;

    (* ASYNC_REG = "TRUE" *) logic [7:0]  virtual_key_cpu_ff1, virtual_key_cpu_ff2;
    (* ASYNC_REG = "TRUE" *) logic [63:0] virtual_sw_cpu_ff1, virtual_sw_cpu_ff2;
    (* ASYNC_REG = "TRUE" *) logic [31:0] cpu_led_50_ff1, cpu_led_50_ff2;
    (* ASYNC_REG = "TRUE" *) logic [39:0] cpu_seg_scan_50_ff1, cpu_seg_scan_50_ff2;
    (* ASYNC_REG = "TRUE" *) logic [31:0] led_pixel_ff1, led_pixel_ff2;
    (* ASYNC_REG = "TRUE" *) logic [31:0] seg_pixel_ff1, seg_pixel_ff2;
    (* ASYNC_REG = "TRUE" *) logic [31:0] last_addr_pixel_ff1, last_addr_pixel_ff2;
    (* ASYNC_REG = "TRUE" *) logic [31:0] last_wdata_pixel_ff1, last_wdata_pixel_ff2;
    (* ASYNC_REG = "TRUE" *) logic [31:0] heartbeat_pixel_ff1, heartbeat_pixel_ff2;
    (* ASYNC_REG = "TRUE" *) logic [31:0] pc_pixel_ff1, pc_pixel_ff2;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  hpd_pixel_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  hlock_pixel_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  clock_pixel_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  reset_pixel_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  anywr_pixel_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  ledwr_pixel_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0]  segwr_pixel_sync;

    logic        anywr_seen;
    logic        ledwr_seen;
    logic        segwr_seen;
    logic [31:0] last_addr;
    logic [31:0] last_wdata;
    logic [31:0] cpu_heartbeat;
    logic [31:0] pc_approx;

    assign o_uart_tx = twin_uart_tx & cpu_uart_tx;
    assign virtual_led = cpu_led_value;
    assign virtual_seg = cpu_seg_scan_value;
    assign virtual_key_cpu = virtual_key_cpu_ff2;
    assign virtual_sw_cpu = virtual_sw_cpu_ff2;
    assign cpu_led_50 = cpu_led_50_ff2;
    assign cpu_seg_scan_50 = cpu_seg_scan_50_ff2;
    assign cpu_reset = ~cpu_clk_locked;
    assign pc_approx = 32'h8000_0000 + {18'd0, inst_addr, 2'b00};

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

    always_ff @(posedge cpu_clk or negedge cpu_clk_locked) begin
        if (!cpu_clk_locked) begin
            virtual_key_cpu_ff1 <= 8'd0;
            virtual_key_cpu_ff2 <= 8'd0;
            virtual_sw_cpu_ff1 <= 64'd0;
            virtual_sw_cpu_ff2 <= 64'd0;
            anywr_seen <= 1'b0;
            ledwr_seen <= 1'b0;
            segwr_seen <= 1'b0;
            last_addr <= 32'h0;
            last_wdata <= 32'h0;
            cpu_heartbeat <= 32'h0;
        end else begin
            virtual_key_cpu_ff1 <= virtual_key_50;
            virtual_key_cpu_ff2 <= virtual_key_cpu_ff1;
            virtual_sw_cpu_ff1 <= virtual_sw_50;
            virtual_sw_cpu_ff2 <= virtual_sw_cpu_ff1;
            cpu_heartbeat <= cpu_heartbeat + 32'd1;

            if (perip_wen) begin
                anywr_seen <= 1'b1;
                last_addr <= perip_addr;
                last_wdata <= perip_wdata;
                if (perip_addr == LED_ADDR) begin
                    ledwr_seen <= 1'b1;
                end
                if (perip_addr == SEG_ADDR) begin
                    segwr_seen <= 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk_50m or negedge cpu_clk_locked) begin
        if (!cpu_clk_locked) begin
            cpu_led_50_ff1 <= 32'd0;
            cpu_led_50_ff2 <= 32'd0;
            cpu_seg_scan_50_ff1 <= 40'd0;
            cpu_seg_scan_50_ff2 <= 40'd0;
        end else begin
            cpu_led_50_ff1 <= cpu_led_value;
            cpu_led_50_ff2 <= cpu_led_50_ff1;
            cpu_seg_scan_50_ff1 <= cpu_seg_scan_value;
            cpu_seg_scan_50_ff2 <= cpu_seg_scan_50_ff1;
        end
    end

    always_ff @(posedge pixel_clk or posedge hdmi_rst) begin
        if (hdmi_rst) begin
            led_pixel_ff1 <= 32'd0;
            led_pixel_ff2 <= 32'd0;
            seg_pixel_ff1 <= 32'd0;
            seg_pixel_ff2 <= 32'd0;
            last_addr_pixel_ff1 <= 32'd0;
            last_addr_pixel_ff2 <= 32'd0;
            last_wdata_pixel_ff1 <= 32'd0;
            last_wdata_pixel_ff2 <= 32'd0;
            heartbeat_pixel_ff1 <= 32'd0;
            heartbeat_pixel_ff2 <= 32'd0;
            pc_pixel_ff1 <= 32'd0;
            pc_pixel_ff2 <= 32'd0;
            hpd_pixel_sync <= 2'b00;
            hlock_pixel_sync <= 2'b00;
            clock_pixel_sync <= 2'b00;
            reset_pixel_sync <= 2'b00;
            anywr_pixel_sync <= 2'b00;
            ledwr_pixel_sync <= 2'b00;
            segwr_pixel_sync <= 2'b00;
        end else begin
            led_pixel_ff1 <= cpu_led_value;
            led_pixel_ff2 <= led_pixel_ff1;
            seg_pixel_ff1 <= cpu_seg_value;
            seg_pixel_ff2 <= seg_pixel_ff1;
            last_addr_pixel_ff1 <= last_addr;
            last_addr_pixel_ff2 <= last_addr_pixel_ff1;
            last_wdata_pixel_ff1 <= last_wdata;
            last_wdata_pixel_ff2 <= last_wdata_pixel_ff1;
            heartbeat_pixel_ff1 <= cpu_heartbeat;
            heartbeat_pixel_ff2 <= heartbeat_pixel_ff1;
            pc_pixel_ff1 <= pc_approx;
            pc_pixel_ff2 <= pc_pixel_ff1;
            hpd_pixel_sync <= {hpd_pixel_sync[0], hdmi_hpd};
            hlock_pixel_sync <= {hlock_pixel_sync[0], hdmi_clk_locked};
            clock_pixel_sync <= {clock_pixel_sync[0], cpu_clk_locked};
            reset_pixel_sync <= {reset_pixel_sync[0], cpu_reset};
            anywr_pixel_sync <= {anywr_pixel_sync[0], anywr_seen};
            ledwr_pixel_sync <= {ledwr_pixel_sync[0], ledwr_seen};
            segwr_pixel_sync <= {segwr_pixel_sync[0], segwr_seen};
        end
    end

    uart #(
        .CLK_FREQ  (50_000_000),
        .BAUD_RATE (9600)
    ) uart_inst (
        .clk      (clk_50m),
        .rst_n    (cpu_clk_locked),
        .rx       (i_uart_rx),
        .rx_data  (rx_data),
        .rx_ready (rx_ready),
        .tx       (twin_uart_tx),
        .tx_data  (tx_data),
        .tx_start (tx_start),
        .tx_busy  (tx_busy)
    );

    twin_controller twin_controller_inst (
        .clk       (clk_50m),
        .rst_n     (cpu_clk_locked),
        .rx_ready  (rx_ready),
        .rx_data   (rx_data),
        .tx_start  (tx_start),
        .tx_data   (tx_data),
        .tx_busy   (tx_busy),
        .sw        (virtual_sw_50),
        .key       (virtual_key_50),
        .seg       (cpu_seg_scan_50),
        .led       (cpu_led_50)
    );

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
        .virtual_sw_input         (virtual_sw_cpu),
        .virtual_key_input        (virtual_key_cpu),
        .uart_rx_i                (i_uart_rx),
        .virtual_seg_output       (cpu_seg_scan_value),
        .virtual_seg_value_output (cpu_seg_value),
        .virtual_led_output       (cpu_led_value),
        .uart_tx_o                (cpu_uart_tx),
        .uart_tx_ready_o          (),
        .uart_rx_valid_o          (),
        .uart_rx_overrun_o        (),
        .uart_rx_data_o           ()
    );

    hdmi_debug_panel hdmi_debug_panel_inst (
        .pixel_clk      (pixel_clk),
        .serial_clk     (serial_clk),
        .rst            (hdmi_rst),
        .led_value      (led_pixel_ff2),
        .seg_value      (seg_pixel_ff2),
        .hpd            (hpd_pixel_sync[1]),
        .hdmi_locked    (hlock_pixel_sync[1]),
        .anywr          (anywr_pixel_sync[1]),
        .ledwr          (ledwr_pixel_sync[1]),
        .segwr          (segwr_pixel_sync[1]),
        .last_addr      (last_addr_pixel_ff2),
        .last_wdata     (last_wdata_pixel_ff2),
        .cpu_heartbeat  (heartbeat_pixel_ff2),
        .cpu_reset      (reset_pixel_sync[1]),
        .cpu_locked     (clock_pixel_sync[1]),
        .pc_value       (pc_pixel_ff2),
        .hdmi_tx_clk_p  (hdmi_tx_clk_p),
        .hdmi_tx_clk_n  (hdmi_tx_clk_n),
        .hdmi_tx_data_p (hdmi_tx_data_p),
        .hdmi_tx_data_n (hdmi_tx_data_n)
    );

endmodule
