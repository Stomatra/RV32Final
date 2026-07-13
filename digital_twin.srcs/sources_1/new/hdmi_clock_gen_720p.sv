`timescale 1ns / 1ps

module hdmi_clock_gen_720p #(
    parameter real    CLKIN1_PERIOD_NS = 8.000,
    parameter real    CLKFBOUT_MULT_F  = 47.500,
    parameter integer DIVCLK_DIVIDE    = 8,
    parameter real    CLKOUT0_DIVIDE_F = 10.000,
    parameter integer CLKOUT1_DIVIDE   = 2
) (
    input  logic clk_in,
    input  logic rst,
    output wire  pixel_clk,
    output wire  pixel_clk_5x,
    output wire  locked
);
    wire clkfb;
    wire clkfb_buf;
    wire pixel_clk_unbuf;
    wire pixel_clk_5x_unbuf;

    MMCME2_BASE #(
        .BANDWIDTH           ("OPTIMIZED"),
        .CLKFBOUT_MULT_F     (CLKFBOUT_MULT_F),
        .CLKFBOUT_PHASE      (0.000),
        .CLKIN1_PERIOD       (CLKIN1_PERIOD_NS),
        .CLKOUT0_DIVIDE_F    (CLKOUT0_DIVIDE_F),
        .CLKOUT0_DUTY_CYCLE  (0.500),
        .CLKOUT0_PHASE       (0.000),
        .CLKOUT1_DIVIDE      (CLKOUT1_DIVIDE),
        .CLKOUT1_DUTY_CYCLE  (0.500),
        .CLKOUT1_PHASE       (0.000),
        .DIVCLK_DIVIDE       (DIVCLK_DIVIDE),
        .REF_JITTER1         (0.010),
        .STARTUP_WAIT        ("FALSE")
    ) mmcm_inst (
        .CLKOUT0    (pixel_clk_unbuf),
        .CLKOUT0B   (),
        .CLKOUT1    (pixel_clk_5x_unbuf),
        .CLKOUT1B   (),
        .CLKOUT2    (),
        .CLKOUT2B   (),
        .CLKOUT3    (),
        .CLKOUT3B   (),
        .CLKOUT4    (),
        .CLKOUT5    (),
        .CLKOUT6    (),
        .CLKFBOUT   (clkfb),
        .CLKFBOUTB  (),
        .LOCKED     (locked),
        .CLKIN1     (clk_in),
        .PWRDWN     (1'b0),
        .RST        (rst),
        .CLKFBIN    (clkfb_buf)
    );

    BUFG bufg_fb (
        .I (clkfb),
        .O (clkfb_buf)
    );

    BUFG bufg_pixel (
        .I (pixel_clk_unbuf),
        .O (pixel_clk)
    );

    BUFG bufg_pixel_5x (
        .I (pixel_clk_5x_unbuf),
        .O (pixel_clk_5x)
    );

endmodule
