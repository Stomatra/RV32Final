`timescale 1ns / 1ps

module hdmi_debug_panel (
    input  logic        pixel_clk,
    input  logic        serial_clk,
    input  logic        rst,
    input  logic [31:0] led_value,
    input  logic [31:0] seg_value,
    input  logic        hpd,
    input  logic        hdmi_locked,
    input  logic        anywr,
    input  logic        ledwr,
    input  logic        segwr,
    input  logic [31:0] last_addr,
    input  logic [31:0] last_wdata,
    input  logic [31:0] cpu_heartbeat,
    input  logic        cpu_reset,
    input  logic        cpu_locked,
    input  logic [31:0] pc_value,
    output wire         hdmi_tx_clk_p,
    output wire         hdmi_tx_clk_n,
    output wire [2:0]   hdmi_tx_data_p,
    output wire [2:0]   hdmi_tx_data_n
);
    logic [10:0] pixel_x;
    logic [9:0]  pixel_y;
    logic        hsync;
    logic        vsync;
    logic        active_video;
    logic        frame_pulse;
    logic [31:0] frame_counter;
    logic [7:0]  red;
    logic [7:0]  green;
    logic [7:0]  blue;
    logic [9:0]  tmds_red;
    logic [9:0]  tmds_green;
    logic [9:0]  tmds_blue;

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

    hdmi_debug_text_overlay overlay_inst (
        .pixel_clk      (pixel_clk),
        .rst            (rst),
        .pixel_x        (pixel_x),
        .pixel_y        (pixel_y),
        .active_video   (active_video),
        .led_value      (led_value),
        .seg_value      (seg_value),
        .hpd            (hpd),
        .hdmi_locked    (hdmi_locked),
        .frame_counter  (frame_counter),
        .anywr          (anywr),
        .ledwr          (ledwr),
        .segwr          (segwr),
        .last_addr      (last_addr),
        .last_wdata     (last_wdata),
        .cpu_heartbeat  (cpu_heartbeat),
        .cpu_reset      (cpu_reset),
        .cpu_locked     (cpu_locked),
        .pc_value       (pc_value),
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

    hdmi_out_7series_ref hdmi_out_inst (
        .pixel_clk          (pixel_clk),
        .serial_clk         (serial_clk),
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
