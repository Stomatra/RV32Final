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

    logic [DATAWIDTH-1:0] add_sub_result;
    logic                 less_signed;
    logic                 less_unsigned;
    logic                 use_subtract;

	// adder_a / adder_b / cin 构成一条统一的加减法器：
	// - 普通加法：A + B + 0
	// - 减法/比较：A + (~B) + 1
    logic [DATAWIDTH-1:0] adder_a, adder_b;
    logic cin, carry;

    assign use_subtract = (ALUOp == ALU_SUB) || (ALUOp == ALU_SLT) || (ALUOp == ALU_SLTU);
    assign adder_a = A;
    assign adder_b = use_subtract ? ~B : B;
    assign cin = use_subtract;

    /* verilator lint_off WIDTHEXPAND */
	// carry 同时用于无符号比较，add_sub_result 的最高位参与有符号比较。
    assign {carry, add_sub_result} = adder_a + adder_b + cin;
    assign less_signed = (A[DATAWIDTH-1] & ~B[DATAWIDTH-1]) |
                         ((~A[DATAWIDTH-1] ^ B[DATAWIDTH-1]) & add_sub_result[DATAWIDTH-1]);
    assign less_unsigned = ~carry;

    assign isTrue = Result[0];

	// 根据 ALUOp 选择最终输出。
    always_comb begin
        Result = '0;
        unique case (ALUOp)
            ALU_ADD,
            ALU_SUB:  Result = add_sub_result;
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