`timescale 1ns / 1ps

module hdmi_out_7series #(
    parameter bit         TMDS_LSB_FIRST   = 1'b1,
    parameter logic [9:0] HDMI_CLK_PATTERN = 10'b0000011111
) (
    input  logic        pixel_clk,
    input  logic        pixel_clk_5x,
    input  logic        rst,
    input  logic [9:0]  tmds_red,
    input  logic [9:0]  tmds_green,
    input  logic [9:0]  tmds_blue,
    output wire         hdmi_tx_clk_p,
    output wire         hdmi_tx_clk_n,
    output wire [2:0]   hdmi_tx_data_p,
    output wire [2:0]   hdmi_tx_data_n
);
    wire [2:0] tmds_serial;
    wire       tmds_clk_serial;

    tmds_serializer_10b #(
        .TMDS_LSB_FIRST (TMDS_LSB_FIRST)
    ) serializer_blue (
        .pixel_clk      (pixel_clk),
        .pixel_clk_5x   (pixel_clk_5x),
        .rst            (rst),
        .parallel_data  (tmds_blue),
        .serial_data    (tmds_serial[0])
    );

    tmds_serializer_10b #(
        .TMDS_LSB_FIRST (TMDS_LSB_FIRST)
    ) serializer_green (
        .pixel_clk      (pixel_clk),
        .pixel_clk_5x   (pixel_clk_5x),
        .rst            (rst),
        .parallel_data  (tmds_green),
        .serial_data    (tmds_serial[1])
    );

    tmds_serializer_10b #(
        .TMDS_LSB_FIRST (TMDS_LSB_FIRST)
    ) serializer_red (
        .pixel_clk      (pixel_clk),
        .pixel_clk_5x   (pixel_clk_5x),
        .rst            (rst),
        .parallel_data  (tmds_red),
        .serial_data    (tmds_serial[2])
    );

    tmds_serializer_10b #(
        .TMDS_LSB_FIRST (TMDS_LSB_FIRST)
    ) serializer_clock (
        .pixel_clk      (pixel_clk),
        .pixel_clk_5x   (pixel_clk_5x),
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

module tmds_serializer_10b #(
    parameter bit TMDS_LSB_FIRST = 1'b1
) (
    input  logic       pixel_clk,
    input  logic       pixel_clk_5x,
    input  logic       rst,
    input  logic [9:0] parallel_data,
    output wire        serial_data
);
    wire shift1;
    wire shift2;
    logic [9:0] oserdes_data;

    always_comb begin
        for (int i = 0; i < 10; i = i + 1) begin
            if (TMDS_LSB_FIRST) begin
                oserdes_data[i] = parallel_data[i];
            end else begin
                oserdes_data[i] = parallel_data[9 - i];
            end
        end
    end

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
        .CLK        (pixel_clk_5x),
        .CLKDIV     (pixel_clk),
        .D1         (oserdes_data[0]),
        .D2         (oserdes_data[1]),
        .D3         (oserdes_data[2]),
        .D4         (oserdes_data[3]),
        .D5         (oserdes_data[4]),
        .D6         (oserdes_data[5]),
        .D7         (oserdes_data[6]),
        .D8         (oserdes_data[7]),
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
        .CLK        (pixel_clk_5x),
        .CLKDIV     (pixel_clk),
        .D1         (1'b0),
        .D2         (1'b0),
        .D3         (oserdes_data[8]),
        .D4         (oserdes_data[9]),
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
