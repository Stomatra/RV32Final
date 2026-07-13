`timescale 1ns / 1ps

module IROM (
    input  logic [11:0] a,
    output logic [31:0] spo
);
    (* rom_style = "distributed" *) logic [31:0] rom [0:4095];
    integer i;

    initial begin
        for (i = 0; i < 4096; i = i + 1) begin
            rom[i] = 32'h00000000;
        end
        rom[0] = 32'h802002B7;
        rom[1] = 32'h04028293;
        rom[2] = 32'h00100313;
        rom[3] = 32'h0062A023;
        rom[4] = 32'h802002B7;
        rom[5] = 32'h02028293;
        rom[6] = 32'h12345337;
        rom[7] = 32'h67830313;
        rom[8] = 32'h0062A023;
        rom[9] = 32'h802002B7;
        rom[10] = 32'h04028293;
        rom[11] = 32'h01000313;
        rom[12] = 32'h0062A023;
        rom[13] = 32'h0000006F;
    end

    always_comb begin
        spo = rom[a];
    end

endmodule
