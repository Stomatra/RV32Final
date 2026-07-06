`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/04/23 12:42:16
// Design Name: 
// Module Name: NPC
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

module NPC#(
    parameter   DATAWIDTH = 32
)(
    input  logic                   isTrue   ,
    input  logic [1:0]             npc_op   ,
    input  logic [DATAWIDTH - 1:0] pc       ,
    input  logic [DATAWIDTH - 1:0] offset   ,
    output logic [DATAWIDTH - 1:0] npc      ,
    output logic [DATAWIDTH - 1:0] pcadd4  
);
	// 旧版 next-PC 选择器：
	// - 默认顺序执行 pc+4
	// - branch 用 isTrue 决定是否跳转到 pc+offset
	// - jalr 直接使用经过对齐处理后的 offset
	// - jal 直接跳到 pc+offset
    logic [DATAWIDTH-1:0] pc_plus_offset;
    logic [DATAWIDTH-1:0] jalr_addr;

    assign pcadd4 = pc + 4;
    assign pc_plus_offset = pc + offset;
	// jalr 目标地址最低位强制清零。
    assign jalr_addr = offset & {{DATAWIDTH - 1{1'b1}}, 1'b0};

    always_comb begin
        case (npc_op)
            2'b01: npc = isTrue ? pc_plus_offset : pcadd4;
            2'b10: npc = jalr_addr;
            2'b11: npc = pc_plus_offset;
            default: npc = pcadd4;
        endcase
    end
endmodule