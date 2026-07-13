`timescale 1ns / 1ps

module hdmi_debug_text_overlay (
    input  logic        pixel_clk,
    input  logic        rst,
    input  logic [10:0] pixel_x,
    input  logic [9:0]  pixel_y,
    input  logic        active_video,
    input  logic [31:0] led_value,
    input  logic [31:0] seg_value,
    input  logic        hpd,
    input  logic        hdmi_locked,
    input  logic [31:0] frame_counter,
    input  logic        anywr,
    input  logic        ledwr,
    input  logic        segwr,
    input  logic [31:0] last_addr,
    input  logic [31:0] last_wdata,
    input  logic [31:0] cpu_heartbeat,
    input  logic        cpu_reset,
    input  logic        cpu_locked,
    input  logic [31:0] pc_value,
    output logic [7:0]  red,
    output logic [7:0]  green,
    output logic [7:0]  blue
);
    localparam int TEXT_X = 64;
    localparam int TEXT_Y = 48;
    localparam int CELL_W = 8;
    localparam int CELL_H = 16;
    localparam int MAX_COLS = 64;
    localparam int MAX_ROWS = 15;
    localparam logic [10:0] TEXT_X_U = 11'd64;
    localparam logic [9:0]  TEXT_Y_U = 10'd48;

    logic        in_text_area;
    logic [10:0] local_x;
    logic [9:0]  local_y;
    logic [5:0]  char_col;
    logic [3:0]  char_row;
    logic [2:0]  glyph_x;
    logic [3:0]  glyph_y;
    logic [7:0]  char_code;
    logic [7:0]  glyph_bits;
    logic        glyph_on;

    function automatic [7:0] hex_ascii(input logic [3:0] nibble);
        begin
            if (nibble < 4'd10) begin
                hex_ascii = 8'h30 + {4'h0, nibble};
            end else begin
                hex_ascii = 8'h41 + {4'h0, nibble - 4'd10};
            end
        end
    endfunction

    function automatic [7:0] hex32_char(input logic [31:0] value, input logic [2:0] index);
        begin
            unique case (index)
                3'd0: hex32_char = hex_ascii(value[31:28]);
                3'd1: hex32_char = hex_ascii(value[27:24]);
                3'd2: hex32_char = hex_ascii(value[23:20]);
                3'd3: hex32_char = hex_ascii(value[19:16]);
                3'd4: hex32_char = hex_ascii(value[15:12]);
                3'd5: hex32_char = hex_ascii(value[11:8]);
                3'd6: hex32_char = hex_ascii(value[7:4]);
                default: hex32_char = hex_ascii(value[3:0]);
            endcase
        end
    endfunction

    function automatic [7:0] debug_char(
        input logic [3:0]  row,
        input logic [5:0]  col,
        input logic [31:0] led,
        input logic [31:0] seg,
        input logic        hpd_v,
        input logic        hlock_v,
        input logic [31:0] frame,
        input logic        anywr_v,
        input logic        ledwr_v,
        input logic        segwr_v,
        input logic [31:0] addr,
        input logic [31:0] wdata,
        input logic [31:0] heartbeat,
        input logic        reset_v,
        input logic        clock_v,
        input logic [31:0] pc
    );
        begin
            debug_char = 8'h20;
            unique case (row)
                4'd0: begin // RV32 CPU DEBUG
                    unique case (col)
                        6'd0:  debug_char = 8'h52; // R
                        6'd1:  debug_char = 8'h56; // V
                        6'd2:  debug_char = 8'h33; // 3
                        6'd3:  debug_char = 8'h32; // 2
                        6'd5:  debug_char = 8'h43; // C
                        6'd6:  debug_char = 8'h50; // P
                        6'd7:  debug_char = 8'h55; // U
                        6'd9:  debug_char = 8'h44; // D
                        6'd10: debug_char = 8'h45; // E
                        6'd11: debug_char = 8'h42; // B
                        6'd12: debug_char = 8'h55; // U
                        6'd13: debug_char = 8'h47; // G
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd1: begin // LED  = 0xXXXXXXXX
                    unique case (col)
                        6'd0: debug_char = 8'h4c;
                        6'd1: debug_char = 8'h45;
                        6'd2: debug_char = 8'h44;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = 8'h30;
                        6'd8: debug_char = 8'h78;
                        6'd9, 6'd10, 6'd11, 6'd12,
                        6'd13, 6'd14, 6'd15, 6'd16:
                            debug_char = hex32_char(led, col[2:0] - 3'd1);
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd2: begin // SEG  = 0xXXXXXXXX
                    unique case (col)
                        6'd0: debug_char = 8'h53;
                        6'd1: debug_char = 8'h45;
                        6'd2: debug_char = 8'h47;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = 8'h30;
                        6'd8: debug_char = 8'h78;
                        6'd9, 6'd10, 6'd11, 6'd12,
                        6'd13, 6'd14, 6'd15, 6'd16:
                            debug_char = hex32_char(seg, col[2:0] - 3'd1);
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd3: begin // ANYWR= X
                    unique case (col)
                        6'd0: debug_char = 8'h41;
                        6'd1: debug_char = 8'h4e;
                        6'd2: debug_char = 8'h59;
                        6'd3: debug_char = 8'h57;
                        6'd4: debug_char = 8'h52;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = anywr_v ? 8'h31 : 8'h30;
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd4: begin // LEDWR= X
                    unique case (col)
                        6'd0: debug_char = 8'h4c;
                        6'd1: debug_char = 8'h45;
                        6'd2: debug_char = 8'h44;
                        6'd3: debug_char = 8'h57;
                        6'd4: debug_char = 8'h52;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = ledwr_v ? 8'h31 : 8'h30;
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd5: begin // SEGWR= X
                    unique case (col)
                        6'd0: debug_char = 8'h53;
                        6'd1: debug_char = 8'h45;
                        6'd2: debug_char = 8'h47;
                        6'd3: debug_char = 8'h57;
                        6'd4: debug_char = 8'h52;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = segwr_v ? 8'h31 : 8'h30;
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd6: begin // ADDR = 0xXXXXXXXX
                    unique case (col)
                        6'd0: debug_char = 8'h41;
                        6'd1: debug_char = 8'h44;
                        6'd2: debug_char = 8'h44;
                        6'd3: debug_char = 8'h52;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = 8'h30;
                        6'd8: debug_char = 8'h78;
                        6'd9, 6'd10, 6'd11, 6'd12,
                        6'd13, 6'd14, 6'd15, 6'd16:
                            debug_char = hex32_char(addr, col[2:0] - 3'd1);
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd7: begin // WDATA= 0xXXXXXXXX
                    unique case (col)
                        6'd0: debug_char = 8'h57;
                        6'd1: debug_char = 8'h44;
                        6'd2: debug_char = 8'h41;
                        6'd3: debug_char = 8'h54;
                        6'd4: debug_char = 8'h41;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = 8'h30;
                        6'd8: debug_char = 8'h78;
                        6'd9, 6'd10, 6'd11, 6'd12,
                        6'd13, 6'd14, 6'd15, 6'd16:
                            debug_char = hex32_char(wdata, col[2:0] - 3'd1);
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd8: begin // HEART= 0xXXXXXXXX
                    unique case (col)
                        6'd0: debug_char = 8'h48;
                        6'd1: debug_char = 8'h45;
                        6'd2: debug_char = 8'h41;
                        6'd3: debug_char = 8'h52;
                        6'd4: debug_char = 8'h54;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = 8'h30;
                        6'd8: debug_char = 8'h78;
                        6'd9, 6'd10, 6'd11, 6'd12,
                        6'd13, 6'd14, 6'd15, 6'd16:
                            debug_char = hex32_char(heartbeat, col[2:0] - 3'd1);
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd9: begin // RESET= X
                    unique case (col)
                        6'd0: debug_char = 8'h52;
                        6'd1: debug_char = 8'h45;
                        6'd2: debug_char = 8'h53;
                        6'd3: debug_char = 8'h45;
                        6'd4: debug_char = 8'h54;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = reset_v ? 8'h31 : 8'h30;
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd10: begin // CPULK= X
                    unique case (col)
                        6'd0: debug_char = 8'h43;
                        6'd1: debug_char = 8'h50;
                        6'd2: debug_char = 8'h55;
                        6'd3: debug_char = 8'h4c;
                        6'd4: debug_char = 8'h4b;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = clock_v ? 8'h31 : 8'h30;
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd11: begin // PC   = 0xXXXXXXXX
                    unique case (col)
                        6'd0: debug_char = 8'h50;
                        6'd1: debug_char = 8'h43;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = 8'h30;
                        6'd8: debug_char = 8'h78;
                        6'd9, 6'd10, 6'd11, 6'd12,
                        6'd13, 6'd14, 6'd15, 6'd16:
                            debug_char = hex32_char(pc, col[2:0] - 3'd1);
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd12: begin // HPD  = X
                    unique case (col)
                        6'd0: debug_char = 8'h48;
                        6'd1: debug_char = 8'h50;
                        6'd2: debug_char = 8'h44;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = hpd_v ? 8'h31 : 8'h30;
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd13: begin // HLOCK= X
                    unique case (col)
                        6'd0: debug_char = 8'h48;
                        6'd1: debug_char = 8'h4c;
                        6'd2: debug_char = 8'h4f;
                        6'd3: debug_char = 8'h43;
                        6'd4: debug_char = 8'h4b;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = hlock_v ? 8'h31 : 8'h30;
                        default: debug_char = 8'h20;
                    endcase
                end
                4'd14: begin // FRAME= 0xXXXXXXXX
                    unique case (col)
                        6'd0: debug_char = 8'h46;
                        6'd1: debug_char = 8'h52;
                        6'd2: debug_char = 8'h41;
                        6'd3: debug_char = 8'h4d;
                        6'd4: debug_char = 8'h45;
                        6'd5: debug_char = 8'h3d;
                        6'd7: debug_char = 8'h30;
                        6'd8: debug_char = 8'h78;
                        6'd9, 6'd10, 6'd11, 6'd12,
                        6'd13, 6'd14, 6'd15, 6'd16:
                            debug_char = hex32_char(frame, col[2:0] - 3'd1);
                        default: debug_char = 8'h20;
                    endcase
                end
                default: debug_char = 8'h20;
            endcase
        end
    endfunction

    always_comb begin
        in_text_area = active_video &&
                       (pixel_x >= TEXT_X) &&
                       (pixel_x < TEXT_X + CELL_W * MAX_COLS) &&
                       (pixel_y >= TEXT_Y) &&
                       (pixel_y < TEXT_Y + CELL_H * MAX_ROWS);
        local_x = pixel_x - TEXT_X_U;
        local_y = pixel_y - TEXT_Y_U;
        char_col = local_x[10:3];
        char_row = local_y[7:4];
        glyph_x = local_x[2:0];
        glyph_y = local_y[3:0];
        char_code = in_text_area ? debug_char(char_row, char_col, led_value, seg_value,
                                              hpd, hdmi_locked, frame_counter,
                                              anywr, ledwr, segwr, last_addr, last_wdata,
                                              cpu_heartbeat, cpu_reset, cpu_locked, pc_value) : 8'h20;
    end

    font_rom_8x16 font_inst (
        .char_code (char_code),
        .row       (glyph_y),
        .pixels    (glyph_bits)
    );

    assign glyph_on = in_text_area && glyph_bits[3'd7 - glyph_x];

    always_ff @(posedge pixel_clk or posedge rst) begin
        if (rst) begin
            red   <= 8'h00;
            green <= 8'h00;
            blue  <= 8'h00;
        end else if (!active_video) begin
            red   <= 8'h00;
            green <= 8'h00;
            blue  <= 8'h00;
        end else if (glyph_on) begin
            if (char_row == 4'd0) begin
                red   <= 8'h90;
                green <= 8'hff;
                blue  <= 8'h90;
            end else begin
                red   <= 8'hff;
                green <= 8'hff;
                blue  <= 8'hff;
            end
        end else begin
            red   <= 8'h00;
            green <= 8'h00;
            blue  <= 8'h00;
        end
    end

endmodule
