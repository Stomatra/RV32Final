`timescale 1ns / 1ps

module hdmi_colorbar_720p_100m_lsb_clkpat_1111100000 (
    input  wire       i_sys_clk_p,
    input  wire       i_sys_clk_n,
    output wire       hdmi_tx_clk_p,
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_data_p,
    output wire [2:0] hdmi_tx_data_n
);
    hdmi_colorbar_720p_top_100m #(
        .TMDS_LSB_FIRST   (1'b1),
        .HDMI_CLK_PATTERN (10'b1111100000)
    ) top_inst (
        .i_sys_clk_p      (i_sys_clk_p),
        .i_sys_clk_n      (i_sys_clk_n),
        .hdmi_tx_clk_p    (hdmi_tx_clk_p),
        .hdmi_tx_clk_n    (hdmi_tx_clk_n),
        .hdmi_tx_data_p   (hdmi_tx_data_p),
        .hdmi_tx_data_n   (hdmi_tx_data_n)
    );
endmodule

module hdmi_colorbar_720p_100m_lsb_clkpat_0000011111 (
    input  wire       i_sys_clk_p,
    input  wire       i_sys_clk_n,
    output wire       hdmi_tx_clk_p,
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_data_p,
    output wire [2:0] hdmi_tx_data_n
);
    hdmi_colorbar_720p_top_100m #(
        .TMDS_LSB_FIRST   (1'b1),
        .HDMI_CLK_PATTERN (10'b0000011111)
    ) top_inst (
        .i_sys_clk_p      (i_sys_clk_p),
        .i_sys_clk_n      (i_sys_clk_n),
        .hdmi_tx_clk_p    (hdmi_tx_clk_p),
        .hdmi_tx_clk_n    (hdmi_tx_clk_n),
        .hdmi_tx_data_p   (hdmi_tx_data_p),
        .hdmi_tx_data_n   (hdmi_tx_data_n)
    );
endmodule

module hdmi_colorbar_720p_100m_msb_clkpat_1111100000 (
    input  wire       i_sys_clk_p,
    input  wire       i_sys_clk_n,
    output wire       hdmi_tx_clk_p,
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_data_p,
    output wire [2:0] hdmi_tx_data_n
);
    hdmi_colorbar_720p_top_100m #(
        .TMDS_LSB_FIRST   (1'b0),
        .HDMI_CLK_PATTERN (10'b1111100000)
    ) top_inst (
        .i_sys_clk_p      (i_sys_clk_p),
        .i_sys_clk_n      (i_sys_clk_n),
        .hdmi_tx_clk_p    (hdmi_tx_clk_p),
        .hdmi_tx_clk_n    (hdmi_tx_clk_n),
        .hdmi_tx_data_p   (hdmi_tx_data_p),
        .hdmi_tx_data_n   (hdmi_tx_data_n)
    );
endmodule

module hdmi_colorbar_720p_100m_msb_clkpat_0000011111 (
    input  wire       i_sys_clk_p,
    input  wire       i_sys_clk_n,
    output wire       hdmi_tx_clk_p,
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_data_p,
    output wire [2:0] hdmi_tx_data_n
);
    hdmi_colorbar_720p_top_100m #(
        .TMDS_LSB_FIRST   (1'b0),
        .HDMI_CLK_PATTERN (10'b0000011111)
    ) top_inst (
        .i_sys_clk_p      (i_sys_clk_p),
        .i_sys_clk_n      (i_sys_clk_n),
        .hdmi_tx_clk_p    (hdmi_tx_clk_p),
        .hdmi_tx_clk_n    (hdmi_tx_clk_n),
        .hdmi_tx_data_p   (hdmi_tx_data_p),
        .hdmi_tx_data_n   (hdmi_tx_data_n)
    );
endmodule
