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
    localparam int DRAM_DEPTH = 65536;

	logic [15:0] dram_addr;
	logic [ 1:0] offset;
	logic [7:0] lane0_wdata, lane1_wdata, lane2_wdata, lane3_wdata;
	logic       lane0_wen, lane1_wen, lane2_wen, lane3_wen;
    integer init_index;

    (* ram_style = "block" *) logic [7:0] dram_lane0 [0:DRAM_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane1 [0:DRAM_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane2 [0:DRAM_DEPTH - 1];
    (* ram_style = "block" *) logic [7:0] dram_lane3 [0:DRAM_DEPTH - 1];

    assign dram_addr = perip_addr[17:2];
    assign offset = perip_addr[1:0];

	initial begin
		for (init_index = 0; init_index < DRAM_DEPTH; init_index = init_index + 1) begin
			dram_lane0[init_index] = 8'h00;
			dram_lane1[init_index] = 8'h00;
			dram_lane2[init_index] = 8'h00;
			dram_lane3[init_index] = 8'h00;
		end

		dram_lane0[16'd3] = 8'hcd;
		dram_lane1[16'd3] = 8'hab;
		dram_lane2[16'd3] = 8'h34;
		dram_lane3[16'd3] = 8'h12;

		dram_lane0[16'd4] = 8'h88;
		dram_lane1[16'd4] = 8'h77;
		dram_lane2[16'd4] = 8'h66;
		dram_lane3[16'd4] = 8'h55;

		dram_lane0[16'd7] = 8'hff;
		dram_lane1[16'd7] = 8'h00;
		dram_lane2[16'd7] = 8'h00;
		dram_lane3[16'd7] = 8'hff;
	end

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
				2'b10: begin
					lane0_wen = 1'b1;
					lane1_wen = 1'b1;
					lane2_wen = 1'b1;
					lane3_wen = 1'b1;
				end
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

    // BRAM synchronous read/write — perip_rdata valid 1 cycle after address
    always_ff @(posedge clk) begin
        if (lane0_wen) dram_lane0[dram_addr] <= lane0_wdata;
        if (lane1_wen) dram_lane1[dram_addr] <= lane1_wdata;
        if (lane2_wen) dram_lane2[dram_addr] <= lane2_wdata;
        if (lane3_wen) dram_lane3[dram_addr] <= lane3_wdata;
        perip_rdata <= {dram_lane3[dram_addr], dram_lane2[dram_addr],
                        dram_lane1[dram_addr], dram_lane0[dram_addr]};
    end
endmodule
