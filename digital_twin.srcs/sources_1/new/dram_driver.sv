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
	input  logic [1:0]	 perip_mask			,
    input  logic         dram_wen           ,
    output logic [31:0]  perip_rdata		
);
	// dram_driver 用四个 byte lane 的同步 BRAM 实现 32bit 数据存储。
	// 每个 lane 独立推断为 block RAM，CPU 通过 perip_mask 做字节/半字/整字写。
    localparam int DRAM_DEPTH = 65536;

	logic [15:0] dram_addr;
	logic [ 1:0] offset;
	logic [7:0] lane0_wdata, lane1_wdata, lane2_wdata, lane3_wdata;
	logic       lane0_wen, lane1_wen, lane2_wen, lane3_wen;
	// 四个 8bit lane 拼成 32bit 宽度。
    (* ram_style = "block" *) logic [7:0] dram_lane0 [0:DRAM_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane1 [0:DRAM_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane2 [0:DRAM_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane3 [0:DRAM_DEPTH - 1];

    assign dram_addr = perip_addr[17:2];
    assign offset = perip_addr[1:0];

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

		// Init words synced from E:/jyd2026/withoutMext/demo/dram.coe.
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

	end

	// 写掩码展开到四个 byte lane。
    always_comb begin
		lane0_wdata = perip_wdata[7:0];
		lane1_wdata = perip_wdata[15:8];
		lane2_wdata = perip_wdata[23:16];
		lane3_wdata = perip_wdata[31:24];

		lane0_wen = 1'b0;
		lane1_wen = 1'b0;
		lane2_wen = 1'b0;
		lane3_wen = 1'b0;

		if (dram_wen) begin
			unique case (perip_mask)
				// 整字写：四个 lane 同时写。
				2'b10: begin
					lane0_wen = 1'b1;
					lane1_wen = 1'b1;
					lane2_wen = 1'b1;
					lane3_wen = 1'b1;
				end
				// 半字写：根据地址 bit[1] 决定低半字还是高半字。
				2'b01: begin
					if (!offset[1]) begin
						lane0_wen = 1'b1;
						lane1_wen = 1'b1;
					end else begin
						lane2_wen = 1'b1;
						lane3_wen = 1'b1;
						lane2_wdata = perip_wdata[7:0];
						lane3_wdata = perip_wdata[15:8];
					end
				end
				// 字节写：把最低 8bit 广播后再按 offset 选 lane。
				2'b00: begin
					lane0_wdata = perip_wdata[7:0];
					lane1_wdata = perip_wdata[7:0];
					lane2_wdata = perip_wdata[7:0];
					lane3_wdata = perip_wdata[7:0];
					unique case (offset)
						2'b00: lane0_wen = 1'b1;
						2'b01: lane1_wen = 1'b1;
						2'b10: lane2_wen = 1'b1;
						2'b11: lane3_wen = 1'b1;
					endcase
				end
				default: begin
					lane0_wen = 1'b1;
					lane1_wen = 1'b1;
					lane2_wen = 1'b1;
					lane3_wen = 1'b1;
				end
			endcase
		end
    end

	// 同步 BRAM 读写：读数据在时钟边沿后更新，天然形成 1 周期返回延迟。
    always_ff @(posedge clk) begin
		if (lane0_wen) dram_lane0[dram_addr] <= lane0_wdata;
		if (lane1_wen) dram_lane1[dram_addr] <= lane1_wdata;
		if (lane2_wen) dram_lane2[dram_addr] <= lane2_wdata;
		if (lane3_wen) dram_lane3[dram_addr] <= lane3_wdata;
		perip_rdata <= {dram_lane3[dram_addr], dram_lane2[dram_addr],
		                dram_lane1[dram_addr], dram_lane0[dram_addr]};
    end
endmodule
