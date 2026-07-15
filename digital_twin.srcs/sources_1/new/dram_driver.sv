`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/22/2025 11:42:01 AM
// Design Name: 
// Module Name: dram_driver
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


module dram_driver(
    input  logic         clk				,

    input  logic [17:0]  perip_addr			,
    input  logic [31:0]  perip_wdata		,
	input  logic [3:0]	 perip_wstrb		,
    output logic [31:0]  perip_rdata		
);
	// dram_driver 用四个 byte lane 的同步 BRAM 实现 32bit 数据存储。
	// 每个 lane 独立推断为 block RAM，由 perip_wstrb 直接控制字节写入。
    localparam int DRAM_DEPTH = 65536;

	logic [15:0] dram_addr;
	// 四个 8bit lane 拼成 32bit 宽度。
    (* ram_style = "block" *) logic [7:0] dram_lane0 [0:DRAM_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane1 [0:DRAM_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane2 [0:DRAM_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane3 [0:DRAM_DEPTH - 1];

    assign dram_addr = perip_addr[17:2];

    integer i;
	initial begin
		// 仿真时先清零，避免未初始化 X 影响测试。
		`ifndef SYNTHESIS
		for (i = 0; i < DRAM_DEPTH; i = i + 1) begin
			dram_lane0[i] = 8'h00;
			dram_lane1[i] = 8'h00;
			dram_lane2[i] = 8'h00;
			dram_lane3[i] = 8'h00;
		end
		`endif

		// Init words synced from E:/jyd2026/withMext/demo/dram.coe.
		dram_lane0[16'd0] = 8'h00;
		dram_lane1[16'd0] = 8'h00;
		dram_lane2[16'd0] = 8'h00;
		dram_lane3[16'd0] = 8'h00;

		dram_lane0[16'd1] = 8'h00;
		dram_lane1[16'd1] = 8'h00;
		dram_lane2[16'd1] = 8'h00;
		dram_lane3[16'd1] = 8'h00;

		dram_lane0[16'd2] = 8'h00;
		dram_lane1[16'd2] = 8'h00;
		dram_lane2[16'd2] = 8'h00;
		dram_lane3[16'd2] = 8'h00;

		dram_lane0[16'd3] = 8'hcd;
		dram_lane1[16'd3] = 8'hab;
		dram_lane2[16'd3] = 8'h34;
		dram_lane3[16'd3] = 8'h12;

		dram_lane0[16'd4] = 8'h88;
		dram_lane1[16'd4] = 8'h77;
		dram_lane2[16'd4] = 8'h66;
		dram_lane3[16'd4] = 8'h55;

		dram_lane0[16'd5] = 8'h00;
		dram_lane1[16'd5] = 8'h00;
		dram_lane2[16'd5] = 8'h00;
		dram_lane3[16'd5] = 8'h00;

		dram_lane0[16'd6] = 8'h00;
		dram_lane1[16'd6] = 8'h00;
		dram_lane2[16'd6] = 8'h00;
		dram_lane3[16'd6] = 8'h00;

		dram_lane0[16'd7] = 8'hff;
		dram_lane1[16'd7] = 8'h00;
		dram_lane2[16'd7] = 8'h00;
		dram_lane3[16'd7] = 8'hff;

		dram_lane0[16'd8] = 8'h00;
		dram_lane1[16'd8] = 8'h00;
		dram_lane2[16'd8] = 8'h00;
		dram_lane3[16'd8] = 8'h00;

		dram_lane0[16'd9] = 8'h00;
		dram_lane1[16'd9] = 8'h00;
		dram_lane2[16'd9] = 8'h00;
		dram_lane3[16'd9] = 8'h00;

		dram_lane0[16'd10] = 8'h00;
		dram_lane1[16'd10] = 8'h00;
		dram_lane2[16'd10] = 8'h00;
		dram_lane3[16'd10] = 8'h00;

		dram_lane0[16'd11] = 8'h00;
		dram_lane1[16'd11] = 8'h00;
		dram_lane2[16'd11] = 8'h00;
		dram_lane3[16'd11] = 8'h00;

		dram_lane0[16'd12] = 8'h00;
		dram_lane1[16'd12] = 8'h00;
		dram_lane2[16'd12] = 8'h00;
		dram_lane3[16'd12] = 8'h00;

		dram_lane0[16'd13] = 8'h00;
		dram_lane1[16'd13] = 8'h00;
		dram_lane2[16'd13] = 8'h00;
		dram_lane3[16'd13] = 8'h00;

	end

	// 同步 BRAM 读写：读数据在时钟边沿后更新，天然形成 1 周期返回延迟。
    always_ff @(posedge clk) begin
		if (perip_wstrb[0]) dram_lane0[dram_addr] <= perip_wdata[7:0];
		if (perip_wstrb[1]) dram_lane1[dram_addr] <= perip_wdata[15:8];
		if (perip_wstrb[2]) dram_lane2[dram_addr] <= perip_wdata[23:16];
		if (perip_wstrb[3]) dram_lane3[dram_addr] <= perip_wdata[31:24];
		perip_rdata <= {dram_lane3[dram_addr], dram_lane2[dram_addr],
		                dram_lane1[dram_addr], dram_lane0[dram_addr]};
    end
endmodule
