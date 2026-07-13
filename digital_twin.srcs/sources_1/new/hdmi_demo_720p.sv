`timescale 1ns / 1ps

module hdmi_demo_720p #(
    parameter bit         TMDS_LSB_FIRST   = 1'b1,
    parameter logic [9:0] HDMI_CLK_PATTERN = 10'b0000011111
) (
    input  logic       pixel_clk,
    input  logic       pixel_clk_5x,
    input  logic       rst,
    output wire        hdmi_tx_clk_p,
    output wire        hdmi_tx_clk_n,
    output wire [2:0]  hdmi_tx_data_p,
    output wire [2:0]  hdmi_tx_data_n,
    output logic [31:0] pixel_tick_counter,
    output logic [31:0] frame_counter
);
    logic [10:0] pixel_x;
    logic [9:0]  pixel_y;
    logic        hsync;
    logic        vsync;
    logic        active_video;
    logic [7:0]  red;
    logic [7:0]  green;
    logic [7:0]  blue;
    logic [9:0]  tmds_red;
    logic [9:0]  tmds_green;
    logic [9:0]  tmds_blue;
    logic        frame_pulse;

    always_ff @(posedge pixel_clk or posedge rst) begin
        if (rst) begin
            pixel_tick_counter <= 32'd0;
        end else begin
            pixel_tick_counter <= pixel_tick_counter + 32'd1;
        end
    end

    video_timing_1280x720 timing_inst (
        .pixel_clk      (pixel_clk),
        .rst            (rst),
        .pixel_x        (pixel_x),
        .pixel_y        (pixel_y),
        .hsync          (hsync),
        .vsync          (vsync),
        .active_video   (active_video),
        .frame_pulse    (frame_pulse),
        .frame_counter  (frame_counter)
    );

    hdmi_test_pattern_720p pattern_inst (
        .pixel_x        (pixel_x),
        .pixel_y        (pixel_y),
        .active_video   (active_video),
        .red            (red),
        .green          (green),
        .blue           (blue)
    );

    tmds_encoder encoder_blue (
        .pixel_clk      (pixel_clk),
        .rst            (rst),
        .video_data     (blue),
        .control0       (hsync),
        .control1       (vsync),
        .video_enable   (active_video),
        .tmds_data      (tmds_blue)
    );

    tmds_encoder encoder_green (
        .pixel_clk      (pixel_clk),
        .rst            (rst),
        .video_data     (green),
        .control0       (1'b0),
        .control1       (1'b0),
        .video_enable   (active_video),
        .tmds_data      (tmds_green)
    );

    tmds_encoder encoder_red (
        .pixel_clk      (pixel_clk),
        .rst            (rst),
        .video_data     (red),
        .control0       (1'b0),
        .control1       (1'b0),
        .video_enable   (active_video),
        .tmds_data      (tmds_red)
    );

    hdmi_out_7series #(
        .TMDS_LSB_FIRST   (TMDS_LSB_FIRST),
        .HDMI_CLK_PATTERN (HDMI_CLK_PATTERN)
    ) hdmi_out_inst (
        .pixel_clk          (pixel_clk),
        .pixel_clk_5x       (pixel_clk_5x),
        .rst                (rst),
        .tmds_red           (tmds_red),
        .tmds_green         (tmds_green),
        .tmds_blue          (tmds_blue),
        .hdmi_tx_clk_p      (hdmi_tx_clk_p),
        .hdmi_tx_clk_n      (hdmi_tx_clk_n),
        .hdmi_tx_data_p     (hdmi_tx_data_p),
        .hdmi_tx_data_n     (hdmi_tx_data_n)
    );

endmodule
