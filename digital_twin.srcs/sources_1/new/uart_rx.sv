`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLK_FREQ_HZ = 260_000_000,
    parameter integer BAUD_RATE   = 115200
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       rx,
    input  logic       clear_valid,
    input  logic       clear_overrun,
    output logic [7:0] rx_data,
    output logic       rx_valid,
    output logic       rx_overrun
);
    localparam integer CLKS_PER_BIT      = CLK_FREQ_HZ / BAUD_RATE;
    localparam integer HALF_CLKS_PER_BIT = CLKS_PER_BIT / 2;
    localparam integer CNT_WIDTH         = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_START,
        ST_DATA,
        ST_STOP
    } rx_state_t;

    rx_state_t state;
    logic [CNT_WIDTH-1:0] clk_cnt;
    logic [2:0] bit_idx;
    logic [7:0] data_shift;
    logic       rx_meta;
    logic       rx_sync;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= ST_IDLE;
            clk_cnt    <= '0;
            bit_idx    <= 3'd0;
            data_shift <= 8'h00;
            rx_data    <= 8'h00;
            rx_valid   <= 1'b0;
            rx_overrun <= 1'b0;
        end else begin
            if (clear_valid) begin
                rx_valid <= 1'b0;
            end
            if (clear_overrun) begin
                rx_overrun <= 1'b0;
            end

            unique case (state)
                ST_IDLE: begin
                    clk_cnt <= '0;
                    bit_idx <= 3'd0;
                    if (!rx_sync) begin
                        state <= ST_START;
                    end
                end

                ST_START: begin
                    if (clk_cnt == HALF_CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        if (!rx_sync) begin
                            state <= ST_DATA;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                ST_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        data_shift[bit_idx] <= rx_sync;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state   <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                ST_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        if (rx_valid && !clear_valid) begin
                            rx_overrun <= 1'b1;
                        end
                        rx_data  <= data_shift;
                        rx_valid <= 1'b1;
                        state    <= ST_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: begin
                    state   <= ST_IDLE;
                    clk_cnt <= '0;
                    bit_idx <= 3'd0;
                end
            endcase
        end
    end

endmodule
