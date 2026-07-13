`timescale 1ns / 1ps

module hdmi_out_7series_ref (
    input  logic        pixel_clk,
    input  logic        serial_clk,
    input  logic        rst,
    input  logic [9:0]  tmds_red,
    input  logic [9:0]  tmds_green,
    input  logic [9:0]  tmds_blue,
    output wire         hdmi_tx_clk_p,
    output wire         hdmi_tx_clk_n,
    output wire [2:0]   hdmi_tx_data_p,
    output wire [2:0]   hdmi_tx_data_n
);
    localparam logic [9:0] HDMI_CLK_PATTERN = 10'b0000011111;

    logic [9:0] tmds_red_q;
    logic [9:0] tmds_green_q;
    logic [9:0] tmds_blue_q;
    wire [2:0]  tmds_serial;
    wire        tmds_clk_serial;

    always_ff @(posedge pixel_clk or posedge rst) begin
        if (rst) begin
            tmds_red_q   <= 10'b1101010100;
            tmds_green_q <= 10'b1101010100;
            tmds_blue_q  <= 10'b1101010100;
        end else begin
            tmds_red_q   <= tmds_red;
            tmds_green_q <= tmds_green;
            tmds_blue_q  <= tmds_blue;
        end
    end

    tmds_serializer_10b_ref serializer_blue (
        .pixel_clk      (pixel_clk),
        .serial_clk     (serial_clk),
        .rst            (rst),
        .parallel_data  (tmds_blue_q),
        .serial_data    (tmds_serial[0])
    );

    tmds_serializer_10b_ref serializer_green (
        .pixel_clk      (pixel_clk),
        .serial_clk     (serial_clk),
        .rst            (rst),
        .parallel_data  (tmds_green_q),
        .serial_data    (tmds_serial[1])
    );

    tmds_serializer_10b_ref serializer_red (
        .pixel_clk      (pixel_clk),
        .serial_clk     (serial_clk),
        .rst            (rst),
        .parallel_data  (tmds_red_q),
        .serial_data    (tmds_serial[2])
    );

    tmds_serializer_10b_ref serializer_clock (
        .pixel_clk      (pixel_clk),
        .serial_clk     (serial_clk),
        .rst            (rst),
        .parallel_data  (HDMI_CLK_PATTERN),
        .serial_data    (tmds_clk_serial)
    );

    OBUFDS obufds_clk (
        .I  (tmds_clk_serial),
        .O  (hdmi_tx_clk_p),
        .OB (hdmi_tx_clk_n)
    );

    genvar i;
    generate
        for (i = 0; i < 3; i = i + 1) begin : gen_data_obufds
            OBUFDS obufds_data (
                .I  (tmds_serial[i]),
                .O  (hdmi_tx_data_p[i]),
                .OB (hdmi_tx_data_n[i])
            );
        end
    endgenerate

endmodule

module tmds_serializer_10b_ref (
    input  logic       pixel_clk,
    input  logic       serial_clk,
    input  logic       rst,
    input  logic [9:0] parallel_data,
    output wire        serial_data
);
    wire shift1;
    wire shift2;

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .INIT_OQ        (1'b0),
        .INIT_TQ        (1'b0),
        .SERDES_MODE    ("MASTER"),
        .SRVAL_OQ       (1'b0),
        .SRVAL_TQ       (1'b0),
        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE"),
        .TRISTATE_WIDTH (1)
    ) oserdes_master (
        .OQ         (serial_data),
        .OFB        (),
        .TQ         (),
        .TFB        (),
        .SHIFTOUT1  (),
        .SHIFTOUT2  (),
        .TBYTEOUT   (),
        .CLK        (serial_clk),
        .CLKDIV     (pixel_clk),
        .D1         (parallel_data[0]),
        .D2         (parallel_data[1]),
        .D3         (parallel_data[2]),
        .D4         (parallel_data[3]),
        .D5         (parallel_data[4]),
        .D6         (parallel_data[5]),
        .D7         (parallel_data[6]),
        .D8         (parallel_data[7]),
        .OCE        (1'b1),
        .RST        (rst),
        .SHIFTIN1   (shift1),
        .SHIFTIN2   (shift2),
        .T1         (1'b0),
        .T2         (1'b0),
        .T3         (1'b0),
        .T4         (1'b0),
        .TBYTEIN    (1'b0),
        .TCE        (1'b0)
    );

    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .INIT_OQ        (1'b0),
        .INIT_TQ        (1'b0),
        .SERDES_MODE    ("SLAVE"),
        .SRVAL_OQ       (1'b0),
        .SRVAL_TQ       (1'b0),
        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE"),
        .TRISTATE_WIDTH (1)
    ) oserdes_slave (
        .OQ         (),
        .OFB        (),
        .TQ         (),
        .TFB        (),
        .SHIFTOUT1  (shift1),
        .SHIFTOUT2  (shift2),
        .TBYTEOUT   (),
        .CLK        (serial_clk),
        .CLKDIV     (pixel_clk),
        .D1         (1'b0),
        .D2         (1'b0),
        .D3         (parallel_data[8]),
        .D4         (parallel_data[9]),
        .D5         (1'b0),
        .D6         (1'b0),
        .D7         (1'b0),
        .D8         (1'b0),
        .OCE        (1'b1),
        .RST        (rst),
        .SHIFTIN1   (1'b0),
        .SHIFTIN2   (1'b0),
        .T1         (1'b0),
        .T2         (1'b0),
        .T3         (1'b0),
        .T4         (1'b0),
        .TBYTEIN    (1'b0),
        .TCE        (1'b0)
    );

endmodule
