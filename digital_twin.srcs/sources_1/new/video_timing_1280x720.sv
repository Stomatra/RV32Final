`timescale 1ns / 1ps

module video_timing_1280x720 (
    input  logic        pixel_clk,
    input  logic        rst,
    output logic [10:0] pixel_x,
    output logic [9:0]  pixel_y,
    output logic        hsync,
    output logic        vsync,
    output logic        active_video,
    output logic        frame_pulse,
    output logic [31:0] frame_counter
);
    localparam int H_ACTIVE = 1280;
    localparam int H_FRONT  = 110;
    localparam int H_SYNC   = 40;
    localparam int H_BACK   = 220;
    localparam int H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;

    localparam int V_ACTIVE = 720;
    localparam int V_FRONT  = 5;
    localparam int V_SYNC   = 5;
    localparam int V_BACK   = 20;
    localparam int V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    localparam int H_SYNC_START = H_ACTIVE + H_FRONT;
    localparam int H_SYNC_END   = H_SYNC_START + H_SYNC;
    localparam int V_SYNC_START = V_ACTIVE + V_FRONT;
    localparam int V_SYNC_END   = V_SYNC_START + V_SYNC;

    logic [10:0] h_count;
    logic [9:0]  v_count;

    always_ff @(posedge pixel_clk or posedge rst) begin
        if (rst) begin
            h_count <= 11'd0;
            v_count <= 10'd0;
            frame_counter <= 32'd0;
            frame_pulse <= 1'b0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= 11'd0;
            if (v_count == V_TOTAL - 1) begin
                v_count <= 10'd0;
                frame_counter <= frame_counter + 32'd1;
                frame_pulse <= 1'b1;
            end else begin
                v_count <= v_count + 10'd1;
                frame_pulse <= 1'b0;
            end
        end else begin
            h_count <= h_count + 11'd1;
            frame_pulse <= 1'b0;
        end
    end

    always_comb begin
        pixel_x      = h_count;
        pixel_y      = v_count;
        active_video = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
        hsync        = (h_count >= H_SYNC_START) && (h_count < H_SYNC_END);
        vsync        = (v_count >= V_SYNC_START) && (v_count < V_SYNC_END);
    end

endmodule
