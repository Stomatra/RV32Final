`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/04/08 12:42:16
// Design Name: 
// Module Name: PC
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

module PC#(
    parameter   DATAWIDTH   = 32              ,
    parameter   RESET_VAL   = 32'h8000_0000
)(
    input  logic                   clk  ,
    input  logic                   rst,
    input  logic [DATAWIDTH - 1:0] npc  ,
    output logic [DATAWIDTH - 1:0] pc_out   
);
	// 简单程序计数器寄存器。
	// 这里保留了一个 rst_delay，用来在复位刚释放后的下一拍再维持一次复位值，
	// 适合某些较早期的启动时序需求。
    logic [DATAWIDTH - 1:0] reg_pc;
    logic rst_delay;

    always_ff @(posedge clk) begin
        rst_delay <= rst;
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst | rst_delay) reg_pc <= 32'h8000_0000;
        else reg_pc <= npc;
    end 

    assign pc_out = reg_pc;
endmodule