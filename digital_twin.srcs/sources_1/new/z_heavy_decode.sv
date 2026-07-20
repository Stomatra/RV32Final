`timescale 1ns / 1ps

module z_heavy_decode (
    input  logic [31:0] instr,
    output logic        z_hit,
    output logic [3:0]  z_op,
    output logic        z_uses_rs1,
    output logic        z_uses_rs2
);
    localparam logic [3:0] ZH_CLZ    = 4'd0;
    localparam logic [3:0] ZH_CTZ    = 4'd1;
    localparam logic [3:0] ZH_CPOP   = 4'd2;
    localparam logic [3:0] ZH_CLMUL  = 4'd3;
    localparam logic [3:0] ZH_CLMULH = 4'd4;
    localparam logic [3:0] ZH_CLMULR = 4'd5;
    localparam logic [3:0] ZH_XPERM4 = 4'd6;
    localparam logic [3:0] ZH_XPERM8 = 4'd7;

    always_comb begin
        z_hit      = 1'b0;
        z_op       = 4'hf;
        z_uses_rs1 = 1'b0;
        z_uses_rs2 = 1'b0;

        if ((instr[6:0] == 7'b0010011) && (instr[14:12] == 3'b001)) begin
            case (instr[31:20])
                12'h600: begin z_hit = 1'b1; z_op = ZH_CLZ;  z_uses_rs1 = 1'b1; end
                12'h601: begin z_hit = 1'b1; z_op = ZH_CTZ;  z_uses_rs1 = 1'b1; end
                12'h602: begin z_hit = 1'b1; z_op = ZH_CPOP; z_uses_rs1 = 1'b1; end
                default: begin end
            endcase
        end else if ((instr[6:0] == 7'b0110011) && (instr[31:25] == 7'b0000101)) begin
            case (instr[14:12])
                3'b001: begin z_hit = 1'b1; z_op = ZH_CLMUL;  z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b1; end
                3'b010: begin z_hit = 1'b1; z_op = ZH_CLMULR; z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b1; end
                3'b011: begin z_hit = 1'b1; z_op = ZH_CLMULH; z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b1; end
                default: begin end
            endcase
        end else if ((instr[6:0] == 7'b0110011) && (instr[31:25] == 7'b0010100)) begin
            case (instr[14:12])
                3'b010: begin z_hit = 1'b1; z_op = ZH_XPERM4; z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b1; end
                3'b100: begin z_hit = 1'b1; z_op = ZH_XPERM8; z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b1; end
                default: begin end
            endcase
        end
    end
endmodule
