`timescale 1ns / 1ps

module z_light_decode (
    input  logic [31:0] instr,

    output logic        z_hit,
    output logic [5:0]  z_op,
    output logic [4:0]  z_shamt,// 
    output logic        z_uses_rs1,
    output logic        z_uses_rs2
);

    localparam logic [6:0] OPC_OP    = 7'b0110011;
    localparam logic [6:0] OPC_OPIMM = 7'b0010011;

    // Z 轻量级指令扩展操作码。
	localparam logic [5:0]  ZOP_ANDN     = 6'd0;// Z 轻量级指令操作码 ANDN，表示按位与非操作。
	localparam logic [5:0]  ZOP_ORN      = 6'd1;// Z 轻量级指令操作码 ORN，表示按位或非操作。
	localparam logic [5:0]  ZOP_XNOR     = 6'd2;// Z 轻量级指令操作码 XNOR，表示按位异或非操作。
	localparam logic [5:0]  ZOP_SEXTB	 = 6'd3;// Z 轻量级指令操作码 SEXTB，表示符号扩展字节操作
	localparam logic [5:0]  ZOP_SEXTH	 = 6'd4;// Z 轻量级指令操作码 SEXTB，表示符号扩展半字操作
	localparam logic [5:0]  ZOP_ZEXTH	 = 6'd5;// Z 轻量级指令操作码 ZEXTH，表示零扩展半字操作
	localparam logic [5:0]  ZOP_ORCB	 = 6'd6;// Z 轻量级指令操作码 ORCB，表示按位或字节操作
	localparam logic [5:0]  ZOP_PACK	 = 6'd7;// Z 轻量级指令操作码 PACK，表示打包操作
	localparam logic [5:0]  ZOP_PACKH	 = 6'd8;// Z 轻量级指令操作码 PACKH，表示打包高半字操作
	localparam logic [5:0]  ZOP_REV8	 = 6'd9;// Z 轻量级指令操作码 REV8，表示按字节反转操作
	localparam logic [5:0]  ZOP_BREV8	 = 6'd10;// Z 轻量级指令操作码 BREV8，表示按字节反转操作
	localparam logic [5:0]  ZOP_ZIP	     = 6'd11;// Z 轻量级指令操作码 ZIP，表示压缩操作
	localparam logic [5:0]  ZOP_UNZIP	 = 6'd12;// Z 轻量级指令操作码 UNZIP，表示解压操作
	localparam logic [5:0]  ZOP_BCLR     = 6'd13;// Z 轻量级指令操作码 BCLR，表示按位清零操作
	localparam logic [5:0]  ZOP_BCLRI    = 6'd14;// Z 轻量级指令操作码 BCLRI，表示按位清零立即数操作
	localparam logic [5:0]  ZOP_BEXT	 = 6'd15;// Z 轻量级指令操作码 BEXT，表示按位提取操作
	localparam logic [5:0]  ZOP_BEXTI	 = 6'd16;// Z 轻量级指令操作码 BEXTI，表示按位提取立即数操作
	localparam logic [5:0]  ZOP_BINV	 = 6'd17;// Z 轻量级指令操作码 BINV，表示按位取反操作
	localparam logic [5:0]  ZOP_BINVI	 = 6'd18;// Z 轻量级指令操作码 BINVI，表示按位取反立即数操作
	localparam logic [5:0]  ZOP_BSET	 = 6'd19;// Z 轻量级指令操作码 BSET，表示按位设置操作
	localparam logic [5:0]  ZOP_BSETI	 = 6'd20;// Z 轻量级指令操作码 BSETI，表示按位设置立即数操作
	localparam logic [5:0]  ZOP_NONE     = 6'd63;// Z 轻量级指令操作码 NONE，表示没有 Z 轻量级指令操作。

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [4:0] rs2;

    assign opcode  = instr[6:0];
    assign funct3  = instr[14:12];
    assign rs2     = instr[24:20];
    assign funct7  = instr[31:25];

    always_comb begin
        z_hit      = 1'b0;
        z_op       = ZOP_NONE;
        z_shamt    = instr[24:20];
        z_uses_rs1 = 1'b0;
        z_uses_rs2 = 1'b0;

        // R-type Z light
        if (opcode == OPC_OP) begin
            unique case ({funct7, funct3})

                // andn / orn / xnor
                {7'h20, 3'b111}: begin
                    z_hit = 1'b1; z_op = ZOP_ANDN;
                    z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b1;
                end

                {7'h20, 3'b110}: begin
                    z_hit = 1'b1; z_op = ZOP_ORN;
                    z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b1;
                end

                {7'h20, 3'b100}: begin
                    z_hit = 1'b1; z_op = ZOP_XNOR;
                    z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b1;
                end

                // pack / zext.h
                {7'h04, 3'b100}: begin
                    z_hit = 1'b1;
                    z_op  = (rs2 == 5'd0) ? ZOP_ZEXTH : ZOP_PACK;
                    z_uses_rs1 = 1'b1;
                    z_uses_rs2 = (rs2 != 5'd0);
                end

                // packh
                {7'h04, 3'b111}: begin
                    z_hit = 1'b1; z_op = ZOP_PACKH;
                    z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b1;
                end

                // bclr / bext / binv / bset
                {7'h24, 3'b001}: begin
                    z_hit = 1'b1; z_op = ZOP_BCLR;
                    z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b1;
                end

                {7'h24, 3'b101}: begin
                    z_hit = 1'b1; z_op = ZOP_BEXT;
                    z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b1;
                end

                {7'h34, 3'b001}: begin
                    z_hit = 1'b1; z_op = ZOP_BINV;
                    z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b1;
                end

                {7'h14, 3'b001}: begin
                    z_hit = 1'b1; z_op = ZOP_BSET;
                    z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b1;
                end

                default: begin end
            endcase
        end

        // I-type Z light
        else if (opcode == OPC_OPIMM) begin
            unique case ({instr[31:20], funct3})

                // sext.b / sext.h
                {12'h604, 3'b001}: begin
                    z_hit = 1'b1; z_op = ZOP_SEXTB;
                    z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b0;
                end

                {12'h605, 3'b001}: begin
                    z_hit = 1'b1; z_op = ZOP_SEXTH;
                    z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b0;
                end

                // orc.b
                {12'h287, 3'b101}: begin
                    z_hit = 1'b1; z_op = ZOP_ORCB;
                    z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b0;
                end

                // rev8 / brev8
                {12'h698, 3'b101}: begin
                    z_hit = 1'b1; z_op = ZOP_REV8;
                    z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b0;
                end

                {12'h687, 3'b101}: begin
                    z_hit = 1'b1; z_op = ZOP_BREV8;
                    z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b0;
                end

                default: begin end
            endcase

            // zip / unzip
            if ((funct7 == 7'h04) && (rs2 == 5'd15) && (funct3 == 3'b001)) begin
                z_hit = 1'b1; z_op = ZOP_ZIP;
                z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b0;
            end

            if ((funct7 == 7'h04) && (rs2 == 5'd15) && (funct3 == 3'b101)) begin
                z_hit = 1'b1; z_op = ZOP_UNZIP;
                z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b0;
            end

            // bclri / bexti / binvi / bseti
            if ((funct7 == 7'h24) && (funct3 == 3'b001)) begin
                z_hit = 1'b1; z_op = ZOP_BCLRI;
                z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b0;
            end

            if ((funct7 == 7'h24) && (funct3 == 3'b101)) begin
                z_hit = 1'b1; z_op = ZOP_BEXTI;
                z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b0;
            end

            if ((funct7 == 7'h34) && (funct3 == 3'b001)) begin
                z_hit = 1'b1; z_op = ZOP_BINVI;
                z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b0;
            end

            if ((funct7 == 7'h14) && (funct3 == 3'b001)) begin
                z_hit = 1'b1; z_op = ZOP_BSETI;
                z_uses_rs1 = 1'b1; z_uses_rs2 = 1'b0;
            end
        end
    end

endmodule