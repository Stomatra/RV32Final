`timescale 1ns / 1ps

module hdmi_colorbar_720p_debug_uart_top (
    input  wire       i_sys_clk_p,
    input  wire       i_sys_clk_n,
    input  wire       hdmi_hpd,
    output wire       o_uart_tx,
    output wire       hdmi_tx_clk_p,
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_data_p,
    output wire [2:0] hdmi_tx_data_n
);
    localparam integer SYS_CLK_FREQ_HZ = 200_000_000;

    wire sys_clk;
    wire pixel_clk;
    wire pixel_clk_5x;
    wire hdmi_clk_locked;
    logic [7:0] reset_shift;
    wire hdmi_rst;
    logic [31:0] pixel_tick_counter_pixel;
    logic [31:0] frame_counter_pixel;
    logic [31:0] pixel_tick_gray_pixel;
    logic [31:0] frame_gray_pixel;
    (* ASYNC_REG = "TRUE" *) logic [31:0] pixel_tick_gray_sys_ff1;
    (* ASYNC_REG = "TRUE" *) logic [31:0] pixel_tick_gray_sys_ff2;
    (* ASYNC_REG = "TRUE" *) logic [31:0] frame_gray_sys_ff1;
    (* ASYNC_REG = "TRUE" *) logic [31:0] frame_gray_sys_ff2;
    logic [31:0] pixel_tick_counter_sys;
    logic [31:0] frame_counter_sys;
    (* ASYNC_REG = "TRUE" *) logic [1:0] locked_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] hpd_sync;

    function automatic [31:0] gray_to_bin(input logic [31:0] gray);
        logic [31:0] value;
        begin
            value[31] = gray[31];
            for (int i = 30; i >= 0; i = i - 1) begin
                value[i] = value[i + 1] ^ gray[i];
            end
            gray_to_bin = value;
        end
    endfunction

    IBUFDS ibufds_sys_clk (
        .I  (i_sys_clk_p),
        .IB (i_sys_clk_n),
        .O  (sys_clk)
    );

    // The shipped CPU PLL is configured for a 200 MHz differential input.
    // 200 / 10 * 37.125 = 742.5 MHz VCO, /10 = 74.25 MHz pixel,
    // /2 = 371.25 MHz 5x TMDS clock.
    hdmi_clock_gen_720p #(
        .CLKIN1_PERIOD_NS (5.000),
        .CLKFBOUT_MULT_F  (37.125),
        .DIVCLK_DIVIDE    (10),
        .CLKOUT0_DIVIDE_F (10.000),
        .CLKOUT1_DIVIDE   (2)
    ) hdmi_clock_gen_inst (
        .clk_in           (sys_clk),
        .rst              (1'b0),
        .pixel_clk        (pixel_clk),
        .pixel_clk_5x     (pixel_clk_5x),
        .locked           (hdmi_clk_locked)
    );

    always_ff @(posedge pixel_clk or negedge hdmi_clk_locked) begin
        if (!hdmi_clk_locked) begin
            reset_shift <= 8'h00;
        end else begin
            reset_shift <= {reset_shift[6:0], 1'b1};
        end
    end

    assign hdmi_rst = ~reset_shift[7];

    hdmi_demo_720p hdmi_demo_inst (
        .pixel_clk              (pixel_clk),
        .pixel_clk_5x           (pixel_clk_5x),
        .rst                    (hdmi_rst),
        .hdmi_tx_clk_p          (hdmi_tx_clk_p),
        .hdmi_tx_clk_n          (hdmi_tx_clk_n),
        .hdmi_tx_data_p         (hdmi_tx_data_p),
        .hdmi_tx_data_n         (hdmi_tx_data_n),
        .pixel_tick_counter     (pixel_tick_counter_pixel),
        .frame_counter          (frame_counter_pixel)
    );

    assign pixel_tick_gray_pixel = pixel_tick_counter_pixel ^ (pixel_tick_counter_pixel >> 1);
    assign frame_gray_pixel      = frame_counter_pixel ^ (frame_counter_pixel >> 1);

    always_ff @(posedge sys_clk) begin
        pixel_tick_gray_sys_ff1 <= pixel_tick_gray_pixel;
        pixel_tick_gray_sys_ff2 <= pixel_tick_gray_sys_ff1;
        frame_gray_sys_ff1 <= frame_gray_pixel;
        frame_gray_sys_ff2 <= frame_gray_sys_ff1;
        locked_sync <= {locked_sync[0], hdmi_clk_locked};
        hpd_sync <= {hpd_sync[0], hdmi_hpd};
    end

    always_comb begin
        pixel_tick_counter_sys = gray_to_bin(pixel_tick_gray_sys_ff2);
        frame_counter_sys = gray_to_bin(frame_gray_sys_ff2);
    end

    hdmi_debug_uart_reporter #(
        .SYS_CLK_FREQ_HZ (SYS_CLK_FREQ_HZ),
        .UART_BAUD_RATE  (115200)
    ) reporter_inst (
        .clk                (sys_clk),
        .rst                (1'b0),
        .mmcm_locked        (locked_sync[1]),
        .hpd                (hpd_sync[1]),
        .pixel_tick_counter (pixel_tick_counter_sys),
        .frame_counter      (frame_counter_sys),
        .uart_tx            (o_uart_tx)
    );

endmodule
