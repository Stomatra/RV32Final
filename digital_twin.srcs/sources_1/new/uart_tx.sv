`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLK_FREQ_HZ = 260_000_000,
    parameter integer BAUD_RATE   = 115200
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       tx_start,
    input  logic [7:0] tx_data,
    output logic       tx_busy,
    output logic       tx
);
    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam integer CNT_WIDTH    = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_START,
        ST_DATA,
        ST_STOP
    } tx_state_t;

    tx_state_t state;
    logic [CNT_WIDTH-1:0] clk_cnt;
    logic [2:0] bit_idx;
    logic [7:0] data_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state   <= ST_IDLE;
            clk_cnt <= '0;
            bit_idx <= 3'd0;
            data_q  <= 8'h00;
            tx_busy <= 1'b0;
            tx      <= 1'b1;
        end else begin
            unique case (state)
                ST_IDLE: begin
                    clk_cnt <= '0;
                    bit_idx <= 3'd0;
                    tx_busy <= 1'b0;
                    tx      <= 1'b1;
                    if (tx_start) begin
                        data_q  <= tx_data;
                        tx_busy <= 1'b1;
                        tx      <= 1'b0;
                        state   <= ST_START;
                    end
                end

                ST_START: begin
                    tx_busy <= 1'b1;
                    tx      <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        bit_idx <= 3'd0;
                        tx      <= data_q[0];
                        state   <= ST_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                ST_DATA: begin
                    tx_busy <= 1'b1;
                    tx      <= data_q[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        if (bit_idx == 3'd7) begin
                            tx    <= 1'b1;
                            state <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                            tx      <= data_q[bit_idx + 3'd1];
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                ST_STOP: begin
                    tx_busy <= 1'b1;
                    tx      <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        tx_busy <= 1'b0;
                        state   <= ST_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: begin
                    state   <= ST_IDLE;
                    clk_cnt <= '0;
                    tx_busy <= 1'b0;
                    tx      <= 1'b1;
                end
            endcase
        end
    end

endmodule
