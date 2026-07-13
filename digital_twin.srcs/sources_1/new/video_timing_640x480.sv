`timescale 1ns / 1ps

module video_timing_640x480 (
    input  logic        pixel_clk,
    input  logic        rst,
    output logic [9:0]  pixel_x,
    output logic [9:0]  pixel_y,
    output logic        hsync,
    output logic        vsync,
    output logic        active_video
);
    localparam int H_ACTIVE = 640;
    localparam int H_FRONT  = 16;
    localparam int H_SYNC   = 96;
    localparam int H_BACK   = 48;
    localparam int H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;

    localparam int V_ACTIVE = 480;
    localparam int V_FRONT  = 10;
    localparam int V_SYNC   = 2;
    localparam int V_BACK   = 33;
    localparam int V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    logic [9:0] h_count;
    logic [9:0] v_count;

    always_ff @(posedge pixel_clk or posedge rst) begin
        if (rst) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= 10'd0;
            if (v_count == V_TOTAL - 1) begin
                v_count <= 10'd0;
            end else begin
                v_count <= v_count + 10'd1;
            end
        end else begin
            h_count <= h_count + 10'd1;
        end
    end

    always_comb begin
        pixel_x = h_count;
        pixel_y = v_count;
        active_video = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
        hsync = ~((h_count >= H_ACTIVE + H_FRONT) &&
                  (h_count <  H_ACTIVE + H_FRONT + H_SYNC));
        vsync = ~((v_count >= V_ACTIVE + V_FRONT) &&
                  (v_count <  V_ACTIVE + V_FRONT + V_SYNC));
    end

endmodule
