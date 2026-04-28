`timescale 1ns / 1ps

module pll (
    input  wire clk_in1_p,
    input  wire clk_in1_n,
    output logic clk_out1,
    output logic clk_out2,
    output logic locked
);
    logic div2;
    logic [3:0] lock_count;

    initial begin
        clk_out1 = 1'b0;
        clk_out2 = 1'b0;
        locked = 1'b0;
        div2 = 1'b0;
        lock_count = 4'd0;
    end

    always @(posedge clk_in1_p) begin
        div2 <= ~div2;
        if (div2) begin
            clk_out1 <= ~clk_out1;
            clk_out2 <= ~clk_out2;
        end

        if (!locked) begin
            lock_count <= lock_count + 1'b1;
            if (lock_count == 4'd7) begin
                locked <= 1'b1;
            end
        end
    end
endmodule
