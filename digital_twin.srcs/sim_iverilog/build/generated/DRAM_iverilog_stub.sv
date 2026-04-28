`timescale 1ns / 1ps

module DRAM (
    input  wire        clk,
    input  wire [15:0] a,
    output logic [31:0] spo,
    input  wire        we,
    input  wire [31:0] d
);
    logic [31:0] mem [0:65535];
    integer idx;

    initial begin
        for (idx = 0; idx < 65536; idx = idx + 1) begin
            mem[idx] = 32'h00000000;
        end
        $readmemh("D:/digital_twin/digital_twin/digital_twin.srcs/sim_iverilog/build/generated/dram.mem", mem);
    end

    always @(*) begin
        spo = mem[a];
    end

    always @(posedge clk) begin
        if (we) begin
            mem[a] <= d;
        end
    end
endmodule
