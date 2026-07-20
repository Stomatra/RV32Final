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
	// dram_driver 鐢ㄥ洓涓?byte lane 鐨勫悓姝?BRAM 瀹炵幇 32bit 鏁版嵁瀛樺偍銆?
	// Four byte lanes form a 32-bit DRAM. Split 64K words into two 32K banks.
	localparam int DRAM_BANK_DEPTH = 32768;

	logic [15:0] dram_addr;
	logic [14:0] bank_addr;
	logic        bank_sel_q;
	logic [31:0] bank0_rdata, bank1_rdata;
	logic [3:0]  bank0_wstrb, bank1_wstrb;
	// bank0 covers the lower 32K words; bank1 covers the upper 32K words.
	(* ram_style = "block" *) logic [7:0] dram_lane0_bank0 [0:DRAM_BANK_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane1_bank0 [0:DRAM_BANK_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane2_bank0 [0:DRAM_BANK_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane3_bank0 [0:DRAM_BANK_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane0_bank1 [0:DRAM_BANK_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane1_bank1 [0:DRAM_BANK_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane2_bank1 [0:DRAM_BANK_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane3_bank1 [0:DRAM_BANK_DEPTH - 1];

    assign dram_addr = perip_addr[17:2];
	assign bank_addr = dram_addr[14:0];
	assign bank0_wstrb = perip_wstrb & {4{~dram_addr[15]}};
	assign bank1_wstrb = perip_wstrb & {4{ dram_addr[15]}};
	assign perip_rdata = bank_sel_q ? bank1_rdata : bank0_rdata;

    integer i;
	initial begin
		// 浠跨湡鏃跺厛娓呴浂锛岄伩鍏嶆湭鍒濆鍖?X 褰卞搷娴嬭瘯銆?
		`ifndef SYNTHESIS
		for (i = 0; i < DRAM_BANK_DEPTH; i = i + 1) begin
			dram_lane0_bank0[i] = 8'h00;
			dram_lane1_bank0[i] = 8'h00;
			dram_lane2_bank0[i] = 8'h00;
			dram_lane3_bank0[i] = 8'h00;
			dram_lane0_bank1[i] = 8'h00;
			dram_lane1_bank1[i] = 8'h00;
			dram_lane2_bank1[i] = 8'h00;
			dram_lane3_bank1[i] = 8'h00;
		end
		`endif

		// Init words synced from E:/jyd2026/withMext/demo/dram.coe.
		dram_lane0_bank0[16'd0] = 8'h00;
		dram_lane1_bank0[16'd0] = 8'h00;
		dram_lane2_bank0[16'd0] = 8'h00;
		dram_lane3_bank0[16'd0] = 8'h00;

		dram_lane0_bank0[16'd1] = 8'h00;
		dram_lane1_bank0[16'd1] = 8'h00;
		dram_lane2_bank0[16'd1] = 8'h00;
		dram_lane3_bank0[16'd1] = 8'h00;

		dram_lane0_bank0[16'd2] = 8'h00;
		dram_lane1_bank0[16'd2] = 8'h00;
		dram_lane2_bank0[16'd2] = 8'h00;
		dram_lane3_bank0[16'd2] = 8'h00;

		dram_lane0_bank0[16'd3] = 8'hcd;
		dram_lane1_bank0[16'd3] = 8'hab;
		dram_lane2_bank0[16'd3] = 8'h34;
		dram_lane3_bank0[16'd3] = 8'h12;

		dram_lane0_bank0[16'd4] = 8'h88;
		dram_lane1_bank0[16'd4] = 8'h77;
		dram_lane2_bank0[16'd4] = 8'h66;
		dram_lane3_bank0[16'd4] = 8'h55;

		dram_lane0_bank0[16'd5] = 8'h00;
		dram_lane1_bank0[16'd5] = 8'h00;
		dram_lane2_bank0[16'd5] = 8'h00;
		dram_lane3_bank0[16'd5] = 8'h00;

		dram_lane0_bank0[16'd6] = 8'h00;
		dram_lane1_bank0[16'd6] = 8'h00;
		dram_lane2_bank0[16'd6] = 8'h00;
		dram_lane3_bank0[16'd6] = 8'h00;

		dram_lane0_bank0[16'd7] = 8'hff;
		dram_lane1_bank0[16'd7] = 8'h00;
		dram_lane2_bank0[16'd7] = 8'h00;
		dram_lane3_bank0[16'd7] = 8'hff;

		dram_lane0_bank0[16'd8] = 8'h00;
		dram_lane1_bank0[16'd8] = 8'h00;
		dram_lane2_bank0[16'd8] = 8'h00;
		dram_lane3_bank0[16'd8] = 8'h00;

		dram_lane0_bank0[16'd9] = 8'h00;
		dram_lane1_bank0[16'd9] = 8'h00;
		dram_lane2_bank0[16'd9] = 8'h00;
		dram_lane3_bank0[16'd9] = 8'h00;

		dram_lane0_bank0[16'd10] = 8'h00;
		dram_lane1_bank0[16'd10] = 8'h00;
		dram_lane2_bank0[16'd10] = 8'h00;
		dram_lane3_bank0[16'd10] = 8'h00;

		dram_lane0_bank0[16'd11] = 8'h00;
		dram_lane1_bank0[16'd11] = 8'h00;
		dram_lane2_bank0[16'd11] = 8'h00;
		dram_lane3_bank0[16'd11] = 8'h00;

		dram_lane0_bank0[16'd12] = 8'h00;
		dram_lane1_bank0[16'd12] = 8'h00;
		dram_lane2_bank0[16'd12] = 8'h00;
		dram_lane3_bank0[16'd12] = 8'h00;

		dram_lane0_bank0[16'd13] = 8'h00;
		dram_lane1_bank0[16'd13] = 8'h00;
		dram_lane2_bank0[16'd13] = 8'h00;
		dram_lane3_bank0[16'd13] = 8'h00;

	end

	// Read both banks synchronously and keep the registered bank select aligned.
	always_ff @(posedge clk) begin
		bank_sel_q <= dram_addr[15];

		bank0_rdata <= {dram_lane3_bank0[bank_addr], dram_lane2_bank0[bank_addr],
		                dram_lane1_bank0[bank_addr], dram_lane0_bank0[bank_addr]};
		bank1_rdata <= {dram_lane3_bank1[bank_addr], dram_lane2_bank1[bank_addr],
		                dram_lane1_bank1[bank_addr], dram_lane0_bank1[bank_addr]};

		if (bank0_wstrb[0]) dram_lane0_bank0[bank_addr] <= perip_wdata[7:0];
		if (bank0_wstrb[1]) dram_lane1_bank0[bank_addr] <= perip_wdata[15:8];
		if (bank0_wstrb[2]) dram_lane2_bank0[bank_addr] <= perip_wdata[23:16];
		if (bank0_wstrb[3]) dram_lane3_bank0[bank_addr] <= perip_wdata[31:24];

		if (bank1_wstrb[0]) dram_lane0_bank1[bank_addr] <= perip_wdata[7:0];
		if (bank1_wstrb[1]) dram_lane1_bank1[bank_addr] <= perip_wdata[15:8];
		if (bank1_wstrb[2]) dram_lane2_bank1[bank_addr] <= perip_wdata[23:16];
		if (bank1_wstrb[3]) dram_lane3_bank1[bank_addr] <= perip_wdata[31:24];
    end
endmodule
