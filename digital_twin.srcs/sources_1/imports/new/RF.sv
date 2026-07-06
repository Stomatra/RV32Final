`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/08 12:42:16
// Design Name: 
// Module Name: RF
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

module RF #(
    parameter   ADDR_WIDTH = 5  ,
    parameter   DATAWIDTH  = 32
)(
    input  logic                    clk            ,
    input  logic                    rst            ,
    // Write rd                   
    input  logic                    wen      ,
    input  logic [ADDR_WIDTH - 1:0] waddr    ,
    input  logic [DATAWIDTH - 1:0]  wdata       ,
    // Read  rs1 rs2
    input  logic [ADDR_WIDTH - 1:0] rR1   ,
    input  logic [ADDR_WIDTH - 1:0] rR2   ,

    output logic [DATAWIDTH - 1:0]  rR1_data  ,
    output logic [DATAWIDTH - 1:0]  rR2_data  ,
    output logic [DATAWIDTH - 1:0]  x1_data   ,
    output logic [DATAWIDTH - 1:0]  x10_data  ,
    output logic [DATAWIDTH - 1:0]  x11_data
);
    // 32 x DATAWIDTH 的通用寄存器堆。
    // - 写口 1 个：wen/waddr/wdata
    // - 读口 2 个：rR1/rR2
    // 另外单独导出 x1/x10/x11，供某些上层快速旁路或 helper 逻辑直接读取。
    logic [DATAWIDTH - 1:0] reg_bank [31:0];

    // 同步写，x0 始终保持 0，不允许写入。
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            for (int i = 0; i < 32; i ++) begin
                reg_bank[i] <= 0;
            end
        end
        else if (wen & (waddr != 5'd0)) begin
            reg_bank[waddr] <= wdata;
        end
    end

	// 组合读口。
    always_comb begin
        rR1_data = reg_bank[rR1];
    end

    always_comb begin
        rR2_data = reg_bank[rR2];
    end

    always_comb begin
        x1_data = reg_bank[5'd1];
    end

    always_comb begin
        x10_data = reg_bank[5'd10];
    end

    always_comb begin
        x11_data = reg_bank[5'd11];
    end

endmodule