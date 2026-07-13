`timescale 1ns / 1ps

module hdmi_test_pattern_720p (
    input  logic [10:0] pixel_x,
    input  logic [9:0]  pixel_y,
    input  logic        active_video,
    output logic [7:0]  red,
    output logic [7:0]  green,
    output logic [7:0]  blue
);
    always_comb begin
        red   = 8'h00;
        green = 8'h00;
        blue  = 8'h00;

        if (active_video) begin
            if (pixel_x < 11'd160) begin
                red   = 8'h00;
                green = 8'h00;
                blue  = 8'h00;
            end else if (pixel_x < 11'd320) begin
                red   = 8'hff;
                green = 8'h00;
                blue  = 8'h00;
            end else if (pixel_x < 11'd480) begin
                red   = 8'h00;
                green = 8'hff;
                blue  = 8'h00;
            end else if (pixel_x < 11'd640) begin
                red   = 8'h00;
                green = 8'h00;
                blue  = 8'hff;
            end else if (pixel_x < 11'd800) begin
                red   = 8'hff;
                green = 8'hff;
                blue  = 8'hff;
            end else if (pixel_x < 11'd960) begin
                red   = 8'hff;
                green = 8'hff;
                blue  = 8'h00;
            end else if (pixel_x < 11'd1120) begin
                red   = 8'h00;
                green = 8'hff;
                blue  = 8'hff;
            end else begin
                red   = 8'hff;
                green = 8'h00;
                blue  = 8'hff;
            end
        end
    end

endmodule
