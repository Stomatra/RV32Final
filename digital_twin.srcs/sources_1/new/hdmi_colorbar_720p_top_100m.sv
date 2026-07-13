`timescale 1ns / 1ps

module hdmi_colorbar_720p_top_100m #(
    parameter bit         TMDS_LSB_FIRST   = 1'b1,
    parameter logic [9:0] HDMI_CLK_PATTERN = 10'b0000011111
) (
    input  wire       i_sys_clk_p,
    input  wire       i_sys_clk_n,
    output wire       hdmi_tx_clk_p,
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_data_p,
    output wire [2:0] hdmi_tx_data_n
);
    wire sys_clk;
    wire pixel_clk;
    wire pixel_clk_5x;
    wire hdmi_clk_locked;
    logic [7:0] reset_shift;
    wire hdmi_rst;

    IBUFDS ibufds_sys_clk (
        .I  (i_sys_clk_p),
        .IB (i_sys_clk_n),
        .O  (sys_clk)
    );

    // Explicit alternate build for a 100 MHz board input clock.
    // 100 / 5 * 37.125 = 742.5 MHz VCO, /10 = 74.25 MHz pixel,
    // /2 = 371.25 MHz 5x TMDS clock.
    hdmi_clock_gen_720p #(
        .CLKIN1_PERIOD_NS (10.000),
        .CLKFBOUT_MULT_F  (37.125),
        .DIVCLK_DIVIDE    (5),
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

    hdmi_demo_720p #(
        .TMDS_LSB_FIRST   (TMDS_LSB_FIRST),
        .HDMI_CLK_PATTERN (HDMI_CLK_PATTERN)
    ) hdmi_demo_inst (
        .pixel_clk          (pixel_clk),
        .pixel_clk_5x       (pixel_clk_5x),
        .rst                (hdmi_rst),
        .hdmi_tx_clk_p      (hdmi_tx_clk_p),
        .hdmi_tx_clk_n      (hdmi_tx_clk_n),
        .hdmi_tx_data_p     (hdmi_tx_data_p),
        .hdmi_tx_data_n     (hdmi_tx_data_n)
    );

endmodule
