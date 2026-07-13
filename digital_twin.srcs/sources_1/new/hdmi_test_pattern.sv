`timescale 1ns / 1ps

module hdmi_test_pattern (
    input  logic [9:0] pixel_x,
    input  logic [9:0] pixel_y,
    input  logic       active_video,
    output logic [7:0] red,
    output logic [7:0] green,
    output logic [7:0] blue
);
    logic [2:0] bar_index;

    always_comb begin
        if (pixel_x < 10'd80) begin
            bar_index = 3'd0;
        end else if (pixel_x < 10'd160) begin
            bar_index = 3'd1;
        end else if (pixel_x < 10'd240) begin
            bar_index = 3'd2;
        end else if (pixel_x < 10'd320) begin
            bar_index = 3'd3;
        end else if (pixel_x < 10'd400) begin
            bar_index = 3'd4;
        end else if (pixel_x < 10'd480) begin
            bar_index = 3'd5;
        end else if (pixel_x < 10'd560) begin
            bar_index = 3'd6;
        end else begin
            bar_index = 3'd7;
        end

        red   = 8'h00;
        green = 8'h00;
        blue  = 8'h00;

        if (active_video) begin
            unique case (bar_index)
                3'd0: {red, green, blue} = {8'h00, 8'h00, 8'h00}; // black
                3'd1: {red, green, blue} = {8'hff, 8'h00, 8'h00}; // red
                3'd2: {red, green, blue} = {8'h00, 8'hff, 8'h00}; // green
                3'd3: {red, green, blue} = {8'h00, 8'h00, 8'hff}; // blue
                3'd4: {red, green, blue} = {8'hff, 8'hff, 8'hff}; // white
                3'd5: {red, green, blue} = {8'hff, 8'hff, 8'h00}; // yellow
                3'd6: {red, green, blue} = {8'h00, 8'hff, 8'hff}; // cyan
                default: {red, green, blue} = {8'hff, 8'h00, 8'hff}; // purple
            endcase
        end
    end

endmodule
