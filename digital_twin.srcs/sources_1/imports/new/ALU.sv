`timescale 1ns / 1ps

module ALU #(
    parameter DATAWIDTH = 32
)(
    input  logic [DATAWIDTH-1:0] A,
    input  logic [DATAWIDTH-1:0] B,
    input  logic [3:0]           ALUOp,
    output logic [DATAWIDTH-1:0] Result,
    output logic                 isTrue
);
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

    logic [DATAWIDTH-1:0] adder_b;
    logic [DATAWIDTH-1:0] add_sub_result;
    logic                 use_subtract;
    logic                 carry;
    logic                 less_signed;
    logic                 less_unsigned;

    assign use_subtract = (ALUOp == ALU_SUB) ||
                          (ALUOp == ALU_SLT) ||
                          (ALUOp == ALU_SLTU);
    assign adder_b = use_subtract ? ~B : B;
    assign {carry, add_sub_result} = A + adder_b + use_subtract;

    assign less_signed = (A[DATAWIDTH-1] & ~B[DATAWIDTH-1]) |
                         ((~A[DATAWIDTH-1] ^ B[DATAWIDTH-1]) &
                          add_sub_result[DATAWIDTH-1]);
    assign less_unsigned = ~carry;
    assign isTrue = Result[0];

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
            ALU_SRA:  Result = $signed(A) >>> B[4:0];
            ALU_SLT:  Result = {{DATAWIDTH-1{1'b0}}, less_signed};
            ALU_SLTU: Result = {{DATAWIDTH-1{1'b0}}, less_unsigned};
            default:  Result = '0;
        endcase
    end
endmodule
