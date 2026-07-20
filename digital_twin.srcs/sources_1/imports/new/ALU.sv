`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/01 10:31:41
// Design Name: 
// Module Name: ALU
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module ALU#(
    parameter   DATAWIDTH = 32	
)(
    input  logic [DATAWIDTH - 1:0]  A           ,
    input  logic [DATAWIDTH - 1:0]  B           ,
    input  logic [3:0]              ALUOp       ,
    output logic [DATAWIDTH - 1:0]  Result      ,
    output logic                    isTrue        
);
	// 组合 ALU。
	// 这里把加法、减法、有符号比较、无符号比较统一复用到一条加/减法链上，
	// 可以减少硬件重复，也方便综合工具把比较逻辑压进加法器进位链。

    localparam logic [3:0] ALU_ADD  = 4'd0;
    localparam logic [3:0] ALU_SUB  = 4'd1;
    localparam logic [3:0] ALU_AND  = 4'd2;
    localparam logic [3:0] ALU_OR   = 4'd3;
    localparam logic [3:0] ALU_XOR  = 4'd4;
    localparam logic [3:0] ALU_SLT  = 4'd5;
    localparam logic [3:0] ALU_SLTU = 4'd6;
    localparam logic [3:0] ALU_SLL  = 4'd7;
    localparam logic [3:0] ALU_SRL  = 4'd8;
    localparam logic [3:0] ALU_SRA  = 4'd9;

    logic [DATAWIDTH-1:0] add_result;
    logic [DATAWIDTH-1:0] sub_result;
    logic                 less_signed;
    logic                 less_unsigned;
    logic                 sub_carry;
    logic [DATAWIDTH:0]   add_ext;
    logic [DATAWIDTH:0]   sub_ext;

	// 加法与减法/比较使用两条独立进位链，使 ALUOp 不进入算术链。
    /* verilator lint_off WIDTHEXPAND */
	// carry 同时用于无符号比较，add_sub_result 的最高位参与有符号比较。
    // Keep ALUOp out of both carry chains. Unlike the earlier parallel version,
    // these nets are not KEEP'ed, so implementation remains free to optimize
    // and place them locally inside the EX pblock.
    assign add_ext = {1'b0, A} + {1'b0, B};
    assign sub_ext = {1'b0, A} + {1'b0, ~B} + {{DATAWIDTH{1'b0}}, 1'b1};
    assign add_result = add_ext[DATAWIDTH-1:0];
    assign sub_result = sub_ext[DATAWIDTH-1:0];
    assign sub_carry = sub_ext[DATAWIDTH];
    assign less_signed = (A[DATAWIDTH-1] & ~B[DATAWIDTH-1]) |
                         ((~A[DATAWIDTH-1] ^ B[DATAWIDTH-1]) & sub_result[DATAWIDTH-1]);
    assign less_unsigned = ~sub_carry;

    assign isTrue = Result[0];

	// 根据 ALUOp 选择最终输出。
    always_comb begin
        Result = '0;
        unique case (ALUOp)
            ALU_ADD:  Result = add_result;
            ALU_SUB:  Result = sub_result;
            ALU_AND:  Result = A & B;
            ALU_OR:   Result = A | B;
            ALU_XOR:  Result = A ^ B;
            ALU_SLL:  Result = A << B[4:0];
            ALU_SRL:  Result = A >> B[4:0];
            ALU_SRA:  Result = ($signed(A)) >>> B[4:0];
            ALU_SLT:  Result = {{DATAWIDTH - 1{1'b0}}, less_signed};
            ALU_SLTU: Result = {{DATAWIDTH - 1{1'b0}}, less_unsigned};
            default: Result = '0;
        endcase
    end

endmodule
