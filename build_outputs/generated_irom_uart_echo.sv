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
        rom[1] = 32'h00100393;
        rom[2] = 32'h0472A023;
        rom[3] = 32'h00000413;
        rom[4] = 32'h0642A303;
        rom[5] = 32'h00437313;
        rom[6] = 32'hFE030CE3;
        rom[7] = 32'h0682A503;
        rom[8] = 32'h0FF57513;
        rom[9] = 32'h00140413;
        rom[10] = 32'h0282A023;
        rom[11] = 32'h00138393;
        rom[12] = 32'h0472A023;
        rom[13] = 32'h02C000EF;
        rom[14] = 32'h00D00593;
        rom[15] = 32'h00B50863;
        rom[16] = 32'h00A00593;
        rom[17] = 32'h00B50463;
        rom[18] = 32'hFC9FF06F;
        rom[19] = 32'h00D00513;
        rom[20] = 32'h010000EF;
        rom[21] = 32'h00A00513;
        rom[22] = 32'h008000EF;
        rom[23] = 32'hFB5FF06F;
        rom[24] = 32'h0642A303;
        rom[25] = 32'h00237313;
        rom[26] = 32'hFE030CE3;
        rom[27] = 32'h06A2A023;
        rom[28] = 32'h00008067;
    end

    always_comb begin
        spo = rom[a];
    end

endmodule
