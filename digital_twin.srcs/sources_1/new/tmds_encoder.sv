`timescale 1ns / 1ps

module tmds_encoder (
    input  logic       pixel_clk,
    input  logic       rst,
    input  logic [7:0] video_data,
    input  logic       control0,
    input  logic       control1,
    input  logic       video_enable,
    output logic [9:0] tmds_data
);
    function automatic [3:0] count_ones8(input logic [7:0] value);
        integer i;
        begin
            count_ones8 = 4'd0;
            for (i = 0; i < 8; i = i + 1) begin
                count_ones8 = count_ones8 + value[i];
            end
        end
    endfunction

    logic [8:0] q_m;
    logic [3:0] data_ones;
    logic [3:0] qm_ones;
    logic       use_xnor;
    logic signed [4:0] qm_balance;
    logic signed [5:0] disparity;

    always_comb begin
        data_ones = count_ones8(video_data);
        use_xnor = (data_ones > 4'd4) || ((data_ones == 4'd4) && (video_data[0] == 1'b0));

        q_m[0] = video_data[0];
        for (int i = 1; i < 8; i = i + 1) begin
            if (use_xnor) begin
                q_m[i] = ~(q_m[i - 1] ^ video_data[i]);
            end else begin
                q_m[i] = q_m[i - 1] ^ video_data[i];
            end
        end
        q_m[8] = ~use_xnor;

        qm_ones = count_ones8(q_m[7:0]);
        qm_balance = $signed({1'b0, qm_ones}) - 5'sd4;
    end

    always_ff @(posedge pixel_clk or posedge rst) begin
        if (rst) begin
            tmds_data <= 10'b1101010100;
            disparity <= 6'sd0;
        end else if (!video_enable) begin
            disparity <= 6'sd0;
            unique case ({control1, control0})
                2'b00: tmds_data <= 10'b1101010100;
                2'b01: tmds_data <= 10'b0010101011;
                2'b10: tmds_data <= 10'b0101010100;
                default: tmds_data <= 10'b1010101011;
            endcase
        end else if ((disparity == 6'sd0) || (qm_balance == 5'sd0)) begin
            tmds_data[9]   <= ~q_m[8];
            tmds_data[8]   <= q_m[8];
            tmds_data[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
            if (q_m[8]) begin
                disparity <= disparity + {{1{qm_balance[4]}}, qm_balance};
            end else begin
                disparity <= disparity - {{1{qm_balance[4]}}, qm_balance};
            end
        end else if (((disparity > 6'sd0) && (qm_balance > 5'sd0)) ||
                     ((disparity < 6'sd0) && (qm_balance < 5'sd0))) begin
            tmds_data[9]   <= 1'b1;
            tmds_data[8]   <= q_m[8];
            tmds_data[7:0] <= ~q_m[7:0];
            disparity <= disparity + (q_m[8] ? 6'sd2 : 6'sd0) -
                          {{1{qm_balance[4]}}, qm_balance};
        end else begin
            tmds_data[9]   <= 1'b0;
            tmds_data[8]   <= q_m[8];
            tmds_data[7:0] <= q_m[7:0];
            disparity <= disparity - (q_m[8] ? 6'sd0 : 6'sd2) +
                          {{1{qm_balance[4]}}, qm_balance};
        end
    end

endmodule
