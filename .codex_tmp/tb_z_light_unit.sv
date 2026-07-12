`timescale 1ns / 1ps

module tb_z_light_unit;
    localparam logic [5:0] ZOP_ANDN   = 6'd0;
    localparam logic [5:0] ZOP_ORN    = 6'd1;
    localparam logic [5:0] ZOP_XNOR   = 6'd2;
    localparam logic [5:0] ZOP_SEXTB  = 6'd3;
    localparam logic [5:0] ZOP_SEXTH  = 6'd4;
    localparam logic [5:0] ZOP_ZEXTH  = 6'd5;
    localparam logic [5:0] ZOP_ORCB   = 6'd6;
    localparam logic [5:0] ZOP_PACK   = 6'd7;
    localparam logic [5:0] ZOP_PACKH  = 6'd8;
    localparam logic [5:0] ZOP_REV8   = 6'd9;
    localparam logic [5:0] ZOP_BREV8  = 6'd10;
    localparam logic [5:0] ZOP_ZIP    = 6'd11;
    localparam logic [5:0] ZOP_UNZIP  = 6'd12;
    localparam logic [5:0] ZOP_BCLR   = 6'd13;
    localparam logic [5:0] ZOP_BCLRI  = 6'd14;
    localparam logic [5:0] ZOP_BEXT   = 6'd15;
    localparam logic [5:0] ZOP_BEXTI  = 6'd16;
    localparam logic [5:0] ZOP_BINV   = 6'd17;
    localparam logic [5:0] ZOP_BINVI  = 6'd18;
    localparam logic [5:0] ZOP_BSET   = 6'd19;
    localparam logic [5:0] ZOP_BSETI  = 6'd20;

    logic [5:0]  op;
    logic [31:0] rs1;
    logic [31:0] rs2;
    logic [4:0]  shamt;
    logic [31:0] result;
    logic        supported;

    z_light_unit dut (
        .z_valid    (1'b1),
        .z_op       (op),
        .rs1_val    (rs1),
        .rs2_val    (rs2),
        .z_shamt    (shamt),
        .z_result   (result),
        .z_supported(supported)
    );

    initial begin
        check(ZOP_ANDN,  32'h1234_80f0, 32'h0f0f_00aa, 5'd0,  32'h1030_8050, "andn");
        check(ZOP_ORN,   32'h1234_80f0, 32'h0f0f_00aa, 5'd0,  32'hf2f4_fff5, "orn");
        check(ZOP_XNOR,  32'h1234_80f0, 32'h0f0f_00aa, 5'd0,  32'he2c4_7fa5, "xnor");
        check(ZOP_SEXTB, 32'h1234_80f0, 32'h0,         5'd0,  32'hffff_fff0, "sext.b");
        check(ZOP_SEXTH, 32'h1234_80f0, 32'h0,         5'd0,  32'hffff_80f0, "sext.h");
        check(ZOP_ZEXTH, 32'h1234_80f0, 32'h0,         5'd0,  32'h0000_80f0, "zext.h");
        check(ZOP_ORCB,  32'h1200_8000, 32'h0,         5'd0,  32'hff00_ff00, "orc.b");
        check(ZOP_PACK,  32'h1234_80f0, 32'h0f0f_00aa, 5'd0,  32'h00aa_80f0, "pack");
        check(ZOP_PACKH, 32'h1234_80f0, 32'h0f0f_00aa, 5'd0,  32'h0000_aaf0, "packh");
        check(ZOP_REV8,  32'h1234_80f0, 32'h0,         5'd0,  32'hf080_3412, "rev8");
        check(ZOP_BREV8, 32'h1234_80f0, 32'h0,         5'd0,  32'h482c_010f, "brev8");
        check(ZOP_ZIP,   32'h0000_ffff, 32'h0,         5'd0,  32'h5555_5555, "zip");
        check(ZOP_UNZIP, 32'h5555_5555, 32'h0,         5'd0,  32'h0000_ffff, "unzip");
        check(ZOP_BCLR,  32'h0000_00ff, 32'h0000_0003, 5'd0,  32'h0000_00f7, "bclr");
        check(ZOP_BCLRI, 32'h0000_00ff, 32'h0,         5'd3,  32'h0000_00f7, "bclri");
        check(ZOP_BEXT,  32'h0000_0080, 32'h0000_0007, 5'd0,  32'h0000_0001, "bext");
        check(ZOP_BEXTI, 32'h0000_0080, 32'h0,         5'd7,  32'h0000_0001, "bexti");
        check(ZOP_BINV,  32'h0000_0000, 32'h0000_0004, 5'd0,  32'h0000_0010, "binv");
        check(ZOP_BINVI, 32'h0000_0000, 32'h0,         5'd4,  32'h0000_0010, "binvi");
        check(ZOP_BSET,  32'h0000_0000, 32'h0000_0005, 5'd0,  32'h0000_0020, "bset");
        check(ZOP_BSETI, 32'h0000_0000, 32'h0,         5'd5,  32'h0000_0020, "bseti");

        $display("[TB] PASS: z_light_unit");
        $finish;
    end

    task automatic check(
        input logic [5:0]  op_i,
        input logic [31:0] rs1_i,
        input logic [31:0] rs2_i,
        input logic [4:0]  shamt_i,
        input logic [31:0] expected,
        input string       name
    );
        begin
            op = op_i;
            rs1 = rs1_i;
            rs2 = rs2_i;
            shamt = shamt_i;
            #1;
            if (!supported || result !== expected) begin
                $error("%s failed: supported=%0b result=%08h expected=%08h",
                       name, supported, result, expected);
                $finish;
            end
        end
    endtask
endmodule
