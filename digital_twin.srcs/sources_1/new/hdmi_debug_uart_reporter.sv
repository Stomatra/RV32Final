`timescale 1ns / 1ps

module hdmi_debug_uart_reporter #(
    parameter integer SYS_CLK_FREQ_HZ = 200_000_000,
    parameter integer UART_BAUD_RATE  = 115200
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        mmcm_locked,
    input  logic        hpd,
    input  logic [31:0] pixel_tick_counter,
    input  logic [31:0] frame_counter,
    output logic        uart_tx
);
    localparam integer REPORT_PERIOD = SYS_CLK_FREQ_HZ;

    typedef enum logic [3:0] {
        ST_WAIT,
        ST_HEADER,
        ST_LOCKED_PREFIX,
        ST_LOCKED_VALUE,
        ST_HPD_PREFIX,
        ST_HPD_VALUE,
        ST_PIXEL_PREFIX,
        ST_PIXEL_HEX,
        ST_FRAME_PREFIX,
        ST_FRAME_HEX,
        ST_TAIL
    } state_t;

    state_t state;
    logic [31:0] period_cnt;
    logic [7:0]  char_idx;
    logic [2:0]  hex_idx;
    logic [31:0] pixel_latched;
    logic [31:0] frame_latched;
    logic        locked_latched;
    logic        hpd_latched;
    logic        tx_start;
    logic [7:0]  tx_data;
    logic        tx_busy;

    uart_tx #(
        .CLK_FREQ_HZ (SYS_CLK_FREQ_HZ),
        .BAUD_RATE   (UART_BAUD_RATE)
    ) uart_tx_inst (
        .clk      (clk),
        .rst      (rst),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx_busy  (tx_busy),
        .tx       (uart_tx)
    );

    function automatic [7:0] hex_char(input logic [3:0] value);
        begin
            hex_char = (value < 4'd10) ? (8'h30 + value) : (8'h41 + value - 4'd10);
        end
    endfunction

    function automatic [7:0] header_char(input logic [7:0] idx);
        begin
            unique case (idx)
                8'd0: header_char = "H";
                8'd1: header_char = "D";
                8'd2: header_char = "M";
                8'd3: header_char = "I";
                8'd4: header_char = " ";
                8'd5: header_char = "D";
                8'd6: header_char = "B";
                8'd7: header_char = "G";
                8'd8: header_char = 8'h0d;
                default: header_char = 8'h0a;
            endcase
        end
    endfunction

    function automatic [7:0] locked_prefix_char(input logic [7:0] idx);
        begin
            unique case (idx)
                8'd0: locked_prefix_char = "m";
                8'd1: locked_prefix_char = "m";
                8'd2: locked_prefix_char = "c";
                8'd3: locked_prefix_char = "m";
                8'd4: locked_prefix_char = "_";
                8'd5: locked_prefix_char = "l";
                8'd6: locked_prefix_char = "o";
                8'd7: locked_prefix_char = "c";
                8'd8: locked_prefix_char = "k";
                8'd9: locked_prefix_char = "e";
                8'd10: locked_prefix_char = "d";
                default: locked_prefix_char = "=";
            endcase
        end
    endfunction

    function automatic [7:0] hpd_prefix_char(input logic [7:0] idx);
        begin
            unique case (idx)
                8'd0: hpd_prefix_char = 8'h0d;
                8'd1: hpd_prefix_char = 8'h0a;
                8'd2: hpd_prefix_char = "h";
                8'd3: hpd_prefix_char = "p";
                8'd4: hpd_prefix_char = "d";
                default: hpd_prefix_char = "=";
            endcase
        end
    endfunction

    function automatic [7:0] pixel_prefix_char(input logic [7:0] idx);
        begin
            unique case (idx)
                8'd0: pixel_prefix_char = 8'h0d;
                8'd1: pixel_prefix_char = 8'h0a;
                8'd2: pixel_prefix_char = "p";
                8'd3: pixel_prefix_char = "i";
                8'd4: pixel_prefix_char = "x";
                8'd5: pixel_prefix_char = "e";
                8'd6: pixel_prefix_char = "l";
                8'd7: pixel_prefix_char = "_";
                8'd8: pixel_prefix_char = "t";
                8'd9: pixel_prefix_char = "i";
                8'd10: pixel_prefix_char = "c";
                8'd11: pixel_prefix_char = "k";
                8'd12: pixel_prefix_char = "_";
                8'd13: pixel_prefix_char = "c";
                8'd14: pixel_prefix_char = "o";
                8'd15: pixel_prefix_char = "u";
                8'd16: pixel_prefix_char = "n";
                8'd17: pixel_prefix_char = "t";
                8'd18: pixel_prefix_char = "e";
                8'd19: pixel_prefix_char = "r";
                8'd20: pixel_prefix_char = "=";
                8'd21: pixel_prefix_char = "0";
                default: pixel_prefix_char = "x";
            endcase
        end
    endfunction

    function automatic [7:0] frame_prefix_char(input logic [7:0] idx);
        begin
            unique case (idx)
                8'd0: frame_prefix_char = 8'h0d;
                8'd1: frame_prefix_char = 8'h0a;
                8'd2: frame_prefix_char = "f";
                8'd3: frame_prefix_char = "r";
                8'd4: frame_prefix_char = "a";
                8'd5: frame_prefix_char = "m";
                8'd6: frame_prefix_char = "e";
                8'd7: frame_prefix_char = "_";
                8'd8: frame_prefix_char = "c";
                8'd9: frame_prefix_char = "o";
                8'd10: frame_prefix_char = "u";
                8'd11: frame_prefix_char = "n";
                8'd12: frame_prefix_char = "t";
                8'd13: frame_prefix_char = "e";
                8'd14: frame_prefix_char = "r";
                8'd15: frame_prefix_char = "=";
                8'd16: frame_prefix_char = "0";
                default: frame_prefix_char = "x";
            endcase
        end
    endfunction

    function automatic [7:0] tail_char(input logic [7:0] idx);
        begin
            unique case (idx)
                8'd0: tail_char = 8'h0d;
                8'd1: tail_char = 8'h0a;
                8'd2: tail_char = 8'h0d;
                default: tail_char = 8'h0a;
            endcase
        end
    endfunction

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_WAIT;
            period_cnt <= 32'd0;
            char_idx <= 8'd0;
            hex_idx <= 3'd0;
            pixel_latched <= 32'd0;
            frame_latched <= 32'd0;
            locked_latched <= 1'b0;
            hpd_latched <= 1'b0;
            tx_start <= 1'b0;
            tx_data <= 8'h00;
        end else begin
            tx_start <= 1'b0;

            unique case (state)
                ST_WAIT: begin
                    char_idx <= 8'd0;
                    hex_idx <= 3'd7;
                    if (period_cnt == REPORT_PERIOD - 1) begin
                        period_cnt <= 32'd0;
                        pixel_latched <= pixel_tick_counter;
                        frame_latched <= frame_counter;
                        locked_latched <= mmcm_locked;
                        hpd_latched <= hpd;
                        state <= ST_HEADER;
                    end else begin
                        period_cnt <= period_cnt + 32'd1;
                    end
                end

                ST_HEADER: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        tx_data <= header_char(char_idx);
                        if (char_idx == 8'd9) begin
                            char_idx <= 8'd0;
                            state <= ST_LOCKED_PREFIX;
                        end else begin
                            char_idx <= char_idx + 8'd1;
                        end
                    end
                end

                ST_LOCKED_PREFIX: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        tx_data <= locked_prefix_char(char_idx);
                        if (char_idx == 8'd11) begin
                            char_idx <= 8'd0;
                            state <= ST_LOCKED_VALUE;
                        end else begin
                            char_idx <= char_idx + 8'd1;
                        end
                    end
                end

                ST_LOCKED_VALUE: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        tx_data <= locked_latched ? "1" : "0";
                        state <= ST_HPD_PREFIX;
                    end
                end

                ST_HPD_PREFIX: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        tx_data <= hpd_prefix_char(char_idx);
                        if (char_idx == 8'd5) begin
                            char_idx <= 8'd0;
                            state <= ST_HPD_VALUE;
                        end else begin
                            char_idx <= char_idx + 8'd1;
                        end
                    end
                end

                ST_HPD_VALUE: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        tx_data <= hpd_latched ? "1" : "0";
                        state <= ST_PIXEL_PREFIX;
                    end
                end

                ST_PIXEL_PREFIX: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        tx_data <= pixel_prefix_char(char_idx);
                        if (char_idx == 8'd22) begin
                            char_idx <= 8'd0;
                            hex_idx <= 3'd7;
                            state <= ST_PIXEL_HEX;
                        end else begin
                            char_idx <= char_idx + 8'd1;
                        end
                    end
                end

                ST_PIXEL_HEX: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        tx_data <= hex_char(pixel_latched[hex_idx * 4 +: 4]);
                        if (hex_idx == 3'd0) begin
                            char_idx <= 8'd0;
                            hex_idx <= 3'd7;
                            state <= ST_FRAME_PREFIX;
                        end else begin
                            hex_idx <= hex_idx - 3'd1;
                        end
                    end
                end

                ST_FRAME_PREFIX: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        tx_data <= frame_prefix_char(char_idx);
                        if (char_idx == 8'd17) begin
                            char_idx <= 8'd0;
                            hex_idx <= 3'd7;
                            state <= ST_FRAME_HEX;
                        end else begin
                            char_idx <= char_idx + 8'd1;
                        end
                    end
                end

                ST_FRAME_HEX: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        tx_data <= hex_char(frame_latched[hex_idx * 4 +: 4]);
                        if (hex_idx == 3'd0) begin
                            char_idx <= 8'd0;
                            state <= ST_TAIL;
                        end else begin
                            hex_idx <= hex_idx - 3'd1;
                        end
                    end
                end

                ST_TAIL: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        tx_data <= tail_char(char_idx);
                        if (char_idx == 8'd3) begin
                            char_idx <= 8'd0;
                            state <= ST_WAIT;
                        end else begin
                            char_idx <= char_idx + 8'd1;
                        end
                    end
                end

                default: state <= ST_WAIT;
            endcase
        end
    end

endmodule
