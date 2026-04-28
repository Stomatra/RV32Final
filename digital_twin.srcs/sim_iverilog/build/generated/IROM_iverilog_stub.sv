`timescale 1ns / 1ps

module IROM (
    input  wire [11:0] a,
    output logic [31:0] spo
);
    logic [31:0] mem [0:4095];
    integer idx;

    initial begin
        for (idx = 0; idx < 4096; idx = idx + 1) begin
            mem[idx] = 32'h00000013;
        end
        $readmemh("D:/digital_twin/digital_twin/digital_twin.srcs/sim_iverilog/build/generated/irom.mem", mem);
    end

    always @(*) begin
        spo = mem[a];
    end
endmodule
