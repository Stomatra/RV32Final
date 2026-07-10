module rv32_multiplier (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,
    input  logic [31:0] rs1,//被乘数
    input  logic [31:0] rs2,//乘数

    output logic        busy,//乘法器正在工作
    output logic        done,//乘法器完成工作
    output logic [31:0] result//乘法器结果
);

    logic [5:0]  cnt;

    logic        signed_op;//是否是有符号乘法
    logic        want_high;//是否需要高位结果

    logic [31:0] multiplicand;//被乘数
    logic [31:0] multiplier;//乘数

    logic [63:0] product;//乘积
endmodule