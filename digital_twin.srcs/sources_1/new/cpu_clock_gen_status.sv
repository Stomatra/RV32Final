`timescale 1ns / 1ps

module cpu_clock_gen_status (
    input  logic clk_in,
    input  logic rst,
    output wire  clk_50m,
    output wire  cpu_clk,
    output wire  locked
);
    wire clkfb;
    wire clkfb_buf;
    wire clk_50m_unbuf;
    wire cpu_clk_unbuf;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (5.000),
        .CLKFBOUT_PHASE     (0.000),
        .CLKIN1_PERIOD      (5.000),
        .CLKOUT0_DIVIDE_F   (20.000),
        .CLKOUT0_DUTY_CYCLE (0.500),
        .CLKOUT0_PHASE      (0.000),
        .CLKOUT1_DIVIDE     (5),
        .CLKOUT1_DUTY_CYCLE (0.500),
        .CLKOUT1_PHASE      (0.000),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) mmcm_inst (
        .CLKOUT0   (clk_50m_unbuf),
        .CLKOUT0B  (),
        .CLKOUT1   (cpu_clk_unbuf),
        .CLKOUT1B  (),
        .CLKOUT2   (),
        .CLKOUT2B  (),
        .CLKOUT3   (),
        .CLKOUT3B  (),
        .CLKOUT4   (),
        .CLKOUT5   (),
        .CLKOUT6   (),
        .CLKFBOUT  (clkfb),
        .CLKFBOUTB (),
        .LOCKED    (locked),
        .CLKIN1    (clk_in),
        .PWRDWN    (1'b0),
        .RST       (rst),
        .CLKFBIN   (clkfb_buf)
    );

    BUFG bufg_fb (
        .I (clkfb),
        .O (clkfb_buf)
    );

    BUFG bufg_50m (
        .I (clk_50m_unbuf),
        .O (clk_50m)
    );

    BUFG bufg_cpu (
        .I (cpu_clk_unbuf),
        .O (cpu_clk)
    );

endmodule
