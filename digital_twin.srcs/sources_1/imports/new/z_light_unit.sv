`timescale 1ns / 1ps

`ifdef ENABLE_Z_B_SMALL
`define Z_LIGHT_UNIT_ENABLE_Z_B_SMALL_DEFAULT 1'b1
`else
`define Z_LIGHT_UNIT_ENABLE_Z_B_SMALL_DEFAULT 1'b0
`endif

module z_light_unit #(
    parameter bit ENABLE_Z_ANDN   = 1'b1,
    parameter bit ENABLE_Z_ORN    = 1'b1,
    parameter bit ENABLE_Z_XNOR   = 1'b1,

    parameter bit ENABLE_Z_SEXTB  = 1'b1,
    parameter bit ENABLE_Z_SEXTH  = 1'b1,
    parameter bit ENABLE_Z_ZEXTH  = 1'b1,

    parameter bit ENABLE_Z_ORCB   = 1'b1,

    parameter bit ENABLE_Z_PACK   = 1'b1,
    parameter bit ENABLE_Z_PACKH  = 1'b1,

    parameter bit ENABLE_Z_REV8   = 1'b1,
    parameter bit ENABLE_Z_BREV8  = 1'b1,
    parameter bit ENABLE_Z_ZIP    = 1'b1,
    parameter bit ENABLE_Z_UNZIP  = 1'b1,

    parameter bit ENABLE_Z_BCLR   = 1'b1,
    parameter bit ENABLE_Z_BCLRI  = 1'b1,
    parameter bit ENABLE_Z_BEXT   = 1'b1,
    parameter bit ENABLE_Z_BEXTI  = 1'b1,
    parameter bit ENABLE_Z_BINV   = 1'b1,
    parameter bit ENABLE_Z_BINVI  = 1'b1,
    parameter bit ENABLE_Z_BSET   = 1'b1,
    parameter bit ENABLE_Z_BSETI  = 1'b1,

    parameter bit ENABLE_Z_B_SMALL = `Z_LIGHT_UNIT_ENABLE_Z_B_SMALL_DEFAULT
)(
    input  logic        z_valid,

    // 由 z_decode 解码出来的操作类型
    input  logic [5:0]  z_op,

    // 源操作数
    input  logic [31:0] rs1_val,
    input  logic [31:0] rs2_val,

    // 立即数版本的 bit index，例如 bseti / bclri / bexti / binvi
    input  logic [4:0]  z_shamt,

    // 结果输出
    output logic [31:0] z_result,

    // 当前 z_op 是否被本模块支持
    output logic        z_supported
);

    // ============================================================
    // z_op 编码
    // 这些编码可以后面放到 z_defs.svh 里统一管理
    // ============================================================

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
    localparam logic [5:0] ZOP_SH1ADD = 6'd21;
    localparam logic [5:0] ZOP_SH2ADD = 6'd22;
    localparam logic [5:0] ZOP_SH3ADD = 6'd23;
    localparam logic [5:0] ZOP_MIN    = 6'd24;
    localparam logic [5:0] ZOP_MINU   = 6'd25;
    localparam logic [5:0] ZOP_MAX    = 6'd26;
    localparam logic [5:0] ZOP_MAXU   = 6'd27;
    localparam logic [5:0] ZOP_ROL    = 6'd28;
    localparam logic [5:0] ZOP_ROR    = 6'd29;
    localparam logic [5:0] ZOP_RORI   = 6'd30;

    function automatic logic [31:0] orc_b_32(input logic [31:0] x);
        begin
            orc_b_32[7:0]    = (|x[7:0])    ? 8'hff : 8'h00;
            orc_b_32[15:8]   = (|x[15:8])   ? 8'hff : 8'h00;
            orc_b_32[23:16]  = (|x[23:16])  ? 8'hff : 8'h00;
            orc_b_32[31:24]  = (|x[31:24])  ? 8'hff : 8'h00;
        end
    endfunction

    function automatic logic [7:0] reverse_byte(input logic [7:0] x);
        begin
            reverse_byte = {x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7]};
        end
    endfunction

    function automatic logic [31:0] rol32(input logic [31:0] x, input logic [4:0] shamt);
        logic [4:0] inv_shamt;
        begin
            inv_shamt = (5'd0 - shamt) & 5'h1f;
            rol32 = (x << shamt) | (x >> inv_shamt);
        end
    endfunction

    function automatic logic [31:0] ror32(input logic [31:0] x, input logic [4:0] shamt);
        logic [4:0] inv_shamt;
        begin
            inv_shamt = (5'd0 - shamt) & 5'h1f;
            ror32 = (x >> shamt) | (x << inv_shamt);
        end
    endfunction

    always_comb begin
        z_result = 32'h0;
        z_supported = 1'b0;
        if(z_valid) begin
            case (z_op)
                ZOP_ANDN: begin
                    if(ENABLE_Z_ANDN) begin
                        z_result = rs1_val & ~rs2_val;
                        z_supported = 1'b1;
                    end
                end
                ZOP_ORN: begin
                    if(ENABLE_Z_ORN) begin
                        z_result = rs1_val | ~rs2_val;
                        z_supported = 1'b1;
                    end
                end
                ZOP_XNOR: begin
                    if(ENABLE_Z_XNOR) begin
                        z_result = ~(rs1_val ^ rs2_val);
                        z_supported = 1'b1;
                    end
                end

                ZOP_SEXTB: begin
                    if(ENABLE_Z_SEXTB) begin
                        z_result = {{24{rs1_val[7]}}, rs1_val[7:0]};
                        z_supported = 1'b1;
                    end
                end
                ZOP_SEXTH: begin
                    if(ENABLE_Z_SEXTH) begin
                        z_result = {{16{rs1_val[15]}}, rs1_val[15:0]};
                        z_supported = 1'b1;
                    end
                end
                ZOP_ZEXTH: begin
                    if(ENABLE_Z_ZEXTH) begin
                        z_result = {16'h0, rs1_val[15:0]};
                        z_supported = 1'b1;
                    end
                end

                ZOP_ORCB: begin
                    if(ENABLE_Z_ORCB) begin
                        z_result = orc_b_32(rs1_val);
                        z_supported = 1'b1;
                    end
                end

                ZOP_PACK: begin
                    if(ENABLE_Z_PACK) begin
                        z_result = {rs2_val[15:0], rs1_val[15:0]};
                        z_supported = 1'b1;
                    end
                end
                ZOP_PACKH: begin
                    if(ENABLE_Z_PACKH) begin
                        z_result = {16'h0, rs2_val[7:0], rs1_val[7:0]};
                        z_supported = 1'b1;
                    end
                end

                ZOP_REV8: begin
                    if(ENABLE_Z_REV8) begin
                        z_result = {rs1_val[7:0], rs1_val[15:8], rs1_val[23:16], rs1_val[31:24]};
                        z_supported = 1'b1;
                    end
                end
                ZOP_BREV8: begin
                    if(ENABLE_Z_BREV8) begin
                        z_result = {reverse_byte(rs1_val[31:24]),
                                    reverse_byte(rs1_val[23:16]),
                                    reverse_byte(rs1_val[15:8]),
                                    reverse_byte(rs1_val[7:0])};
                        z_supported = 1'b1;
                    end
                end
                ZOP_ZIP: begin
                    if(ENABLE_Z_ZIP) begin
                        z_result = {rs1_val[31], rs1_val[15], rs1_val[30], rs1_val[14],
                                    rs1_val[29], rs1_val[13], rs1_val[28], rs1_val[12],
                                    rs1_val[27], rs1_val[11], rs1_val[26], rs1_val[10],
                                    rs1_val[25], rs1_val[9],  rs1_val[24], rs1_val[8],
                                    rs1_val[23], rs1_val[7],  rs1_val[22], rs1_val[6],
                                    rs1_val[21], rs1_val[5],  rs1_val[20], rs1_val[4],
                                    rs1_val[19], rs1_val[3],  rs1_val[18], rs1_val[2],
                                    rs1_val[17], rs1_val[1],  rs1_val[16], rs1_val[0]};
                        z_supported = 1'b1;
                    end
                end
                ZOP_UNZIP: begin
                    if(ENABLE_Z_UNZIP) begin
                        z_result = {rs1_val[31], rs1_val[29], rs1_val[27], rs1_val[25],
                                    rs1_val[23], rs1_val[21], rs1_val[19], rs1_val[17],
                                    rs1_val[15], rs1_val[13], rs1_val[11], rs1_val[9],
                                    rs1_val[7],  rs1_val[5],  rs1_val[3],  rs1_val[1],
                                    rs1_val[30], rs1_val[28], rs1_val[26], rs1_val[24],
                                    rs1_val[22], rs1_val[20], rs1_val[18], rs1_val[16],
                                    rs1_val[14], rs1_val[12], rs1_val[10], rs1_val[8],
                                    rs1_val[6],  rs1_val[4],  rs1_val[2],  rs1_val[0]};
                        z_supported = 1'b1;
                    end
                end

                ZOP_BCLR: begin
                    if(ENABLE_Z_BCLR) begin
                        z_result = rs1_val & ~(32'h1 << rs2_val[4:0]);
                        z_supported = 1'b1;
                    end
                end
                ZOP_BCLRI: begin
                    if(ENABLE_Z_BCLRI) begin
                        z_result = rs1_val & ~(32'h1 << z_shamt);
                        z_supported = 1'b1;
                    end
                end
                ZOP_BEXT: begin
                    if(ENABLE_Z_BEXT) begin
                        z_result = (rs1_val >> rs2_val[4:0]) & 32'h1;
                        z_supported = 1'b1;
                    end
                end
                ZOP_BEXTI: begin
                    if(ENABLE_Z_BEXTI) begin
                        z_result = (rs1_val >> z_shamt) & 32'h1;
                        z_supported = 1'b1;
                    end
                end
                ZOP_BINV: begin
                    if(ENABLE_Z_BINV) begin
                        z_result = rs1_val ^ (32'h1 << rs2_val[4:0]);
                        z_supported = 1'b1;
                    end
                end
                ZOP_BINVI: begin
                    if(ENABLE_Z_BINVI) begin
                        z_result = rs1_val ^ (32'h1 << z_shamt);
                        z_supported = 1'b1;
                    end
                end
                ZOP_BSET: begin
                    if(ENABLE_Z_BSET) begin
                        z_result = rs1_val | (32'h1 << rs2_val[4:0]);
                        z_supported = 1'b1;
                    end
                end
                ZOP_BSETI: begin
                    if(ENABLE_Z_BSETI) begin
                        z_result = rs1_val | (32'h1 << z_shamt);
                        z_supported = 1'b1;
                    end
                end

                ZOP_SH1ADD: begin
                    if (ENABLE_Z_B_SMALL) begin
                        z_result = (rs1_val << 1) + rs2_val;
                        z_supported = 1'b1;
                    end
                end
                ZOP_SH2ADD: begin
                    if (ENABLE_Z_B_SMALL) begin
                        z_result = (rs1_val << 2) + rs2_val;
                        z_supported = 1'b1;
                    end
                end
                ZOP_SH3ADD: begin
                    if (ENABLE_Z_B_SMALL) begin
                        z_result = (rs1_val << 3) + rs2_val;
                        z_supported = 1'b1;
                    end
                end
                ZOP_MIN: begin
                    if (ENABLE_Z_B_SMALL) begin
                        z_result = ($signed(rs1_val) < $signed(rs2_val)) ? rs1_val : rs2_val;
                        z_supported = 1'b1;
                    end
                end
                ZOP_MINU: begin
                    if (ENABLE_Z_B_SMALL) begin
                        z_result = (rs1_val < rs2_val) ? rs1_val : rs2_val;
                        z_supported = 1'b1;
                    end
                end
                ZOP_MAX: begin
                    if (ENABLE_Z_B_SMALL) begin
                        z_result = ($signed(rs1_val) > $signed(rs2_val)) ? rs1_val : rs2_val;
                        z_supported = 1'b1;
                    end
                end
                ZOP_MAXU: begin
                    if (ENABLE_Z_B_SMALL) begin
                        z_result = (rs1_val > rs2_val) ? rs1_val : rs2_val;
                        z_supported = 1'b1;
                    end
                end
                ZOP_ROL: begin
                    if (ENABLE_Z_B_SMALL) begin
                        z_result = rol32(rs1_val, rs2_val[4:0]);
                        z_supported = 1'b1;
                    end
                end
                ZOP_ROR: begin
                    if (ENABLE_Z_B_SMALL) begin
                        z_result = ror32(rs1_val, rs2_val[4:0]);
                        z_supported = 1'b1;
                    end
                end
                ZOP_RORI: begin
                    if (ENABLE_Z_B_SMALL) begin
                        z_result = ror32(rs1_val, z_shamt);
                        z_supported = 1'b1;
                    end
                end

                default: begin
                    z_result = 32'h0;
                    z_supported = 1'b0;
                end
            endcase
        end
    end
endmodule

`undef Z_LIGHT_UNIT_ENABLE_Z_B_SMALL_DEFAULT
