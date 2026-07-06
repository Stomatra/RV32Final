`timescale 1ns / 1ps

module myCPU #(
	parameter ENABLE_MUL_HELPER_ACCEL = 1'b0
) (
	input  logic         cpu_rst,
	input  logic         cpu_clk,

	output logic [11:0]  irom_addr,
	input  logic [31:0]  irom_data,

	output logic [31:0]  perip_addr,
	output logic         perip_wen,
	output logic [1:0]   perip_mask,
	output logic [31:0]  perip_wdata,
	input  logic [31:0]  perip_rdata
);
	localparam logic [31:0] RESET_PC      = 32'h8000_0000;
	localparam logic [31:0] NOP_INSTR     = 32'h0000_0013;
	localparam logic [31:0] MUL_HELPER_PC = 32'h8000_1fa8;
	localparam logic [31:0] MUL_HELPER_LOOP004_RA = 32'h8000_04c8;
	localparam logic [31:0] MUL_HELPER_LOOP006_RA = 32'h8000_0734;

	localparam logic [6:0]  OPC_LUI       = 7'b0110111;
	localparam logic [6:0]  OPC_AUIPC     = 7'b0010111;
	localparam logic [6:0]  OPC_JAL       = 7'b1101111;
	localparam logic [6:0]  OPC_JALR      = 7'b1100111;
	localparam logic [6:0]  OPC_BRANCH    = 7'b1100011;
	localparam logic [6:0]  OPC_LOAD      = 7'b0000011;
	localparam logic [6:0]  OPC_STORE     = 7'b0100011;
	localparam logic [6:0]  OPC_OPIMM     = 7'b0010011;
	localparam logic [6:0]  OPC_OP        = 7'b0110011;

	localparam logic [3:0]  ALU_ADD       = 4'd0;
	localparam logic [3:0]  ALU_SUB       = 4'd1;
	localparam logic [3:0]  ALU_AND       = 4'd2;
	localparam logic [3:0]  ALU_OR        = 4'd3;
	localparam logic [3:0]  ALU_XOR       = 4'd4;
	localparam logic [3:0]  ALU_SLT       = 4'd5;
	localparam logic [3:0]  ALU_SLTU      = 4'd6;
	localparam logic [3:0]  ALU_SLL       = 4'd7;
	localparam logic [3:0]  ALU_SRL       = 4'd8;
	localparam logic [3:0]  ALU_SRA       = 4'd9;

	localparam logic        ALU_SRC_A_RS1 = 1'b0;
	localparam logic        ALU_SRC_A_PC  = 1'b1;

	localparam logic [1:0]  ALU_SRC_B_RS2   = 2'd0;
	localparam logic [1:0]  ALU_SRC_B_IMM_I = 2'd1;
	localparam logic [1:0]  ALU_SRC_B_IMM_S = 2'd2;
	localparam logic [1:0]  ALU_SRC_B_IMM_U = 2'd3;

	localparam logic [1:0]  WB_SRC_ALU    = 2'd0;
	localparam logic [1:0]  WB_SRC_MEM    = 2'd1;
	localparam logic [1:0]  WB_SRC_PC4    = 2'd2;
	localparam logic [1:0]  WB_SRC_IMM_U  = 2'd3;

	localparam logic [1:0]  PC_SRC_PC4    = 2'd0;
	localparam logic [1:0]  PC_SRC_BRANCH = 2'd1;
	localparam logic [1:0]  PC_SRC_JAL    = 2'd2;
	localparam logic [1:0]  PC_SRC_JALR   = 2'd3;

	localparam logic [1:0]  MEM_MASK_BYTE = 2'b00;
	localparam logic [1:0]  MEM_MASK_HALF = 2'b01;
	localparam logic [1:0]  MEM_MASK_WORD = 2'b10;

	logic [31:0] pc_q;
	logic [31:0] pc_next;

	logic [31:0] ifid_pc;
	logic [31:0] ifid_instr;
	logic        ifid_valid;

	logic [6:0]  id_opcode;
	logic [6:0]  id_funct7;
	logic [2:0]  id_funct3;
	logic [4:0]  id_rd;
	logic [4:0]  id_rs1;
	logic [4:0]  id_rs2;
	logic [31:0] id_imm_raw;
	logic [31:0] id_imm;
	logic [31:0] id_rs1_val;
	logic [31:0] id_rs2_val;
	logic [31:0] rf_rs1_raw;
	logic [31:0] rf_rs2_raw;
	logic [31:0] rf_x1_raw;
	logic [31:0] rf_x10_raw;
	logic [31:0] rf_x11_raw;
	logic        id_uses_rs1;
	logic        id_uses_rs2;
	logic        load_use_hazard;
	logic        mem_load_stall;
	logic        mem_stall_flag;
	logic        id_mul_helper_candidate;
	logic        id_mul_helper_return_match;
	logic        id_mul_helper_hit;
	logic [31:0] id_mul_helper_ra;
	logic [31:0] id_mul_helper_lhs;
	logic [31:0] id_mul_helper_rhs;
	logic        id_rf_we;
	logic [1:0]  id_wb_sel;
	logic        id_alu_src_a_sel;
	logic [1:0]  id_alu_src_b_sel;
	logic [3:0]  id_alu_op;
	logic [1:0]  id_pc_sel;
	logic        id_mem_req;
	logic        id_mem_write;
	logic [1:0]  id_mem_mask;

	logic [31:0] idex_pc;
	logic [4:0]  idex_rs1;
	logic [4:0]  idex_rs2;
	logic [31:0] idex_rs1_val;
	logic [31:0] idex_rs2_val;
	logic        idex_uses_rs1;
	logic        idex_uses_rs2;
	logic [4:0]  idex_rd;
	logic [31:0] idex_imm;
	logic [2:0]  idex_funct3;
	logic        idex_valid;
	logic        idex_mul_helper;
	logic [31:0] idex_mul_helper_ra;
	logic [31:0] idex_mul_helper_lhs;
	logic [31:0] idex_mul_helper_rhs;
	logic        idex_rf_we;
	logic [1:0]  idex_wb_sel;
	logic        idex_alu_src_a_sel;
	logic [1:0]  idex_alu_src_b_sel;
	logic [3:0]  idex_alu_op;
	logic [1:0]  idex_pc_sel;
	logic        idex_mem_req;
	logic        idex_mem_write;
	logic [1:0]  idex_mem_mask;

	logic [31:0] ex_rs1_val;
	logic [31:0] ex_rs2_val;
	logic [31:0] ex_pc_rs1_val;
	logic [31:0] ex_pc_rs2_val;
	logic [31:0] ex_alu_a;
	logic [31:0] ex_alu_b;
	logic [31:0] ex_alu_y;
	logic        ex_br_take;
	logic        ex_pc_use_rs1;
	logic        ex_pc_use_rs2;
	logic        ex_pc_fwd_rs1_from_exmem;
	logic        ex_pc_fwd_rs1_from_memwb;
	logic        ex_pc_fwd_rs2_from_exmem;
	logic        ex_pc_fwd_rs2_from_memwb;
	logic        ex_alu_is_true;
	logic        ex_cmp_eq;
	logic        ex_cmp_lt_signed;
	logic        ex_cmp_lt_unsigned;
	logic [31:0] ex_pc4;
	logic [31:0] ex_pc_plus_imm;
	logic [31:0] ex_jalr_sum;
	logic [31:0] ex_jalr_target;
	logic [63:0] ex_mul_helper_full;
	logic [31:0] ex_mul_helper_result;
	logic        ex_pc_redirect;
	logic [31:0] ex_pc_target;
	logic [31:0] ex_wb_data;
	logic [31:0] ex_store_data;
	logic        ex_use_rs1_value;
	logic        ex_use_rs2_value;
	logic        ex_fwd_rs1_from_exmem;
	logic        ex_fwd_rs1_from_memwb;
	logic        ex_fwd_rs2_from_exmem;
	logic        ex_fwd_rs2_from_memwb;
	logic        exmem_can_forward;
	logic        memwb_can_forward;

	logic [31:0] exmem_alu_y      = 32'h0;
	logic [31:0] exmem_store_data = 32'h0;
	logic [4:0]  exmem_rd         = 5'h0;
	logic [2:0]  exmem_funct3     = 3'h0;
	logic        exmem_valid      = 1'b0;
	logic [31:0] exmem_wb_data    = 32'h0;
	logic        exmem_rf_we      = 1'b0;
	logic [1:0]  exmem_wb_sel     = WB_SRC_ALU;
	logic        exmem_mem_req    = 1'b0;
	logic        exmem_mem_write  = 1'b0;
	logic [1:0]  exmem_mem_mask   = MEM_MASK_WORD;
	logic [31:0] exmem_pc         = 32'h0;
	logic [31:0] exmem_addr_base  = 32'h0;
	logic [31:0] exmem_addr_off   = 32'h0;

	logic [31:0] mem_load_data;
	logic [31:0] mem_wb_data;

	logic [31:0] memwb_wdata;
	logic [4:0]  memwb_rd;
	logic        memwb_rf_we;
	logic        memwb_valid;
	logic [31:0] memwb_pc;

	function automatic logic [1:0] decode_mem_mask(input logic [2:0] funct3);
		begin
			case (funct3)
				3'b000,
				3'b100: decode_mem_mask = MEM_MASK_BYTE;
				3'b001,
				3'b101: decode_mem_mask = MEM_MASK_HALF;
				default: decode_mem_mask = MEM_MASK_WORD;
			endcase
		end
	endfunction

	function automatic logic [31:0] forward_helper_reg(
		input logic [4:0]  reg_addr,
		input logic [31:0] rf_value
	);
		begin
			if (reg_addr == 5'd0) begin
				forward_helper_reg = 32'h0;
			end else begin
				forward_helper_reg = rf_value;
				if (idex_valid && idex_rf_we && (idex_rd == reg_addr) && (idex_rd != 5'd0) &&
					(idex_wb_sel != WB_SRC_MEM)) begin
					forward_helper_reg = ex_wb_data;
				end else if (exmem_valid && exmem_rf_we && (exmem_rd == reg_addr) && (exmem_rd != 5'd0) &&
					(exmem_wb_sel != WB_SRC_MEM)) begin
					forward_helper_reg = exmem_wb_data;
				end else if (memwb_valid && memwb_rf_we && (memwb_rd == reg_addr) && (memwb_rd != 5'd0)) begin
					forward_helper_reg = memwb_wdata;
				end
			end
		end
	endfunction

	function automatic logic [31:0] forward_helper_operand_reg(
		input logic [4:0]  reg_addr,
		input logic [31:0] rf_value
	);
		begin
			if (reg_addr == 5'd0) begin
				forward_helper_operand_reg = 32'h0;
			end else begin
				forward_helper_operand_reg = rf_value;
				if (exmem_valid && exmem_rf_we && (exmem_rd == reg_addr) && (exmem_rd != 5'd0) &&
					(exmem_wb_sel != WB_SRC_MEM)) begin
					forward_helper_operand_reg = exmem_wb_data;
				end else if (memwb_valid && memwb_rf_we && (memwb_rd == reg_addr) && (memwb_rd != 5'd0)) begin
					forward_helper_operand_reg = memwb_wdata;
				end
			end
		end
	endfunction

	assign irom_addr   = pc_q[13:2];
	assign perip_addr  = exmem_alu_y;
	assign perip_wen   = exmem_valid && exmem_mem_req && exmem_mem_write;
	assign perip_mask  = exmem_mem_mask;
	assign perip_wdata = exmem_store_data;

	mycpu_rv32_decode u_dec (
		.instr  (ifid_instr),
		.opcode (id_opcode),
		.funct3 (id_funct3),
		.funct7 (id_funct7),
		.rd     (id_rd),
		.rs1    (id_rs1),
		.rs2    (id_rs2)
	);

	IMMGEN #(32) u_imm (
		.instr (ifid_instr),
		.imm   (id_imm_raw)
	);

	RF #(5, 32) u_rf (
		.clk     (cpu_clk),
		.rst     (cpu_rst),
		.wen     (memwb_rf_we && memwb_valid),
		.waddr   (memwb_rd),
		.wdata   (memwb_wdata),
		.rR1     (id_rs1),
		.rR2     (id_rs2),
		.rR1_data(rf_rs1_raw),
		.rR2_data(rf_rs2_raw),
		.x1_data (rf_x1_raw),
		.x10_data(rf_x10_raw),
		.x11_data(rf_x11_raw)
	);

	ALU #(32) u_alu (
		.A          (ex_alu_a),
		.B          (ex_alu_b),
		.ALUOp      (idex_alu_op),
		.Result     (ex_alu_y),
		.isTrue     (ex_alu_is_true)
	);

	assign ex_store_data    = idex_mem_write ? ex_rs2_val : 32'h0;
	assign ex_pc4           = idex_pc + 32'd4;
	assign ex_pc_plus_imm   = idex_pc + idex_imm;

	always_comb begin
		if (idex_valid && (idex_pc_sel == PC_SRC_JALR)) begin
			ex_jalr_sum = ex_pc_rs1_val + idex_imm;
		end else begin
			ex_jalr_sum = 32'h0;
		end
	end

	assign ex_jalr_target   = {ex_jalr_sum[31:1], 1'b0};
	assign ex_mul_helper_full     = $unsigned(idex_mul_helper_lhs) * $unsigned(idex_mul_helper_rhs);
	assign ex_mul_helper_result   = ex_mul_helper_full[31:0];
	assign id_mul_helper_candidate = ENABLE_MUL_HELPER_ACCEL && ifid_valid && !idex_mul_helper && (ifid_pc == MUL_HELPER_PC);
	assign id_mul_helper_ra       = id_mul_helper_candidate ? forward_helper_reg(5'd1, rf_x1_raw) : 32'h0;
	assign id_mul_helper_return_match = (id_mul_helper_ra == MUL_HELPER_LOOP004_RA) ||
									 (id_mul_helper_ra == MUL_HELPER_LOOP006_RA);
	assign id_mul_helper_hit      = id_mul_helper_candidate && id_mul_helper_return_match;
	assign id_mul_helper_lhs      = id_mul_helper_hit ? forward_helper_operand_reg(5'd10, rf_x10_raw) : 32'h0;
	assign id_mul_helper_rhs      = id_mul_helper_hit ? forward_helper_operand_reg(5'd11, rf_x11_raw) : 32'h0;
	assign id_imm           = (id_opcode == OPC_BRANCH) ? {{19{ifid_instr[31]}}, ifid_instr[31], ifid_instr[7], ifid_instr[30:25], ifid_instr[11:8], 1'b0} :
							  (id_opcode == OPC_JAL)    ? {{11{ifid_instr[31]}}, ifid_instr[31], ifid_instr[19:12], ifid_instr[20], ifid_instr[30:21], 1'b0} :
							  id_imm_raw;
	assign exmem_can_forward = exmem_rf_we && (exmem_rd != 5'h0) && (exmem_wb_sel != WB_SRC_MEM);
	assign memwb_can_forward = memwb_rf_we && (memwb_rd != 5'h0);
	assign ex_use_rs1_value = idex_valid && idex_uses_rs1;
	assign ex_use_rs2_value = idex_valid && idex_uses_rs2;
	assign ex_pc_use_rs1 = idex_valid && ((idex_pc_sel == PC_SRC_BRANCH) || (idex_pc_sel == PC_SRC_JALR));
	assign ex_pc_use_rs2 = idex_valid && (idex_pc_sel == PC_SRC_BRANCH);
	assign ex_fwd_rs1_from_exmem = ex_use_rs1_value && exmem_can_forward && (exmem_rd == idex_rs1);
	assign ex_fwd_rs1_from_memwb = ex_use_rs1_value && memwb_can_forward && (memwb_rd == idex_rs1);
	assign ex_fwd_rs2_from_exmem = ex_use_rs2_value && exmem_can_forward && (exmem_rd == idex_rs2);
	assign ex_fwd_rs2_from_memwb = ex_use_rs2_value && memwb_can_forward && (memwb_rd == idex_rs2);
	assign ex_pc_fwd_rs1_from_exmem = ex_pc_use_rs1 && exmem_can_forward && (exmem_rd == idex_rs1);
	assign ex_pc_fwd_rs1_from_memwb = ex_pc_use_rs1 && memwb_can_forward && (memwb_rd == idex_rs1);
	assign ex_pc_fwd_rs2_from_exmem = ex_pc_use_rs2 && exmem_can_forward && (exmem_rd == idex_rs2);
	assign ex_pc_fwd_rs2_from_memwb = ex_pc_use_rs2 && memwb_can_forward && (memwb_rd == idex_rs2);

	always_comb begin
		ex_cmp_eq = 1'b0;
		ex_cmp_lt_signed = 1'b0;
		ex_cmp_lt_unsigned = 1'b0;
		if (idex_pc_sel == PC_SRC_BRANCH) begin
			ex_cmp_eq = (ex_pc_rs1_val == ex_pc_rs2_val);
			ex_cmp_lt_signed = ($signed(ex_pc_rs1_val) < $signed(ex_pc_rs2_val));
			ex_cmp_lt_unsigned = (ex_pc_rs1_val < ex_pc_rs2_val);
		end
	end

	always_comb begin
		if (id_rs1 == 5'd0) begin
			id_rs1_val = 32'h0;
		end else if (memwb_can_forward && (memwb_rd == id_rs1)) begin
			id_rs1_val = memwb_wdata;
		end else begin
			id_rs1_val = rf_rs1_raw;
		end

		if (id_rs2 == 5'd0) begin
			id_rs2_val = 32'h0;
		end else if (memwb_can_forward && (memwb_rd == id_rs2)) begin
			id_rs2_val = memwb_wdata;
		end else begin
			id_rs2_val = rf_rs2_raw;
		end
	end

	always_comb begin
		if (ex_pc_redirect) begin
			pc_next = ex_pc_target;
		end else if (load_use_hazard || mem_load_stall) begin
			pc_next = pc_q;
		end else begin
			pc_next = pc_q + 32'd4;
		end
	end

	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			pc_q <= RESET_PC;
		end else begin
			pc_q <= pc_next;
		end
	end

	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			ifid_pc    <= RESET_PC;
			ifid_instr <= NOP_INSTR;
		end else if (!load_use_hazard && !mem_load_stall) begin
			ifid_pc    <= pc_q;
			ifid_instr <= irom_data;
		end
	end

	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			ifid_valid <= 1'b0;
		end else if (mem_load_stall) begin
			// hold IF/ID valid while the MEM-stage load bubble is extended
		end else if (ex_pc_redirect) begin
			ifid_valid <= 1'b0;
		end else if (!load_use_hazard) begin
			ifid_valid <= 1'b1;
		end
	end

	always_comb begin
		id_uses_rs1      = 1'b0;
		id_uses_rs2      = 1'b0;
		id_rf_we         = 1'b0;
		id_wb_sel        = WB_SRC_ALU;
		id_alu_src_a_sel = ALU_SRC_A_RS1;
		id_alu_src_b_sel = ALU_SRC_B_RS2;
		id_alu_op        = ALU_ADD;
		id_pc_sel        = PC_SRC_PC4;
		id_mem_req       = 1'b0;
		id_mem_write     = 1'b0;
		id_mem_mask      = MEM_MASK_WORD;

		if (ifid_valid) begin
			case (id_opcode)
				OPC_LUI: begin
					id_rf_we  = 1'b1;
					id_wb_sel = WB_SRC_IMM_U;
				end

				OPC_AUIPC: begin
					id_rf_we         = 1'b1;
					id_wb_sel        = WB_SRC_ALU;
					id_alu_src_a_sel = ALU_SRC_A_PC;
					id_alu_src_b_sel = ALU_SRC_B_IMM_U;
				end

				OPC_JAL: begin
					id_rf_we  = 1'b1;
					id_wb_sel = WB_SRC_PC4;
					id_pc_sel = PC_SRC_JAL;
				end

				OPC_JALR: begin
					id_uses_rs1      = 1'b1;
					id_rf_we         = 1'b1;
					id_wb_sel        = WB_SRC_PC4;
					id_alu_src_a_sel = ALU_SRC_A_RS1;
					id_alu_src_b_sel = ALU_SRC_B_IMM_I;
					id_pc_sel        = PC_SRC_JALR;
				end

				OPC_BRANCH: begin
					id_uses_rs1 = 1'b1;
					id_uses_rs2 = 1'b1;
					id_pc_sel   = PC_SRC_BRANCH;
				end

				OPC_OPIMM: begin
					id_uses_rs1      = 1'b1;
					id_rf_we         = 1'b1;
					id_wb_sel        = WB_SRC_ALU;
					id_alu_src_a_sel = ALU_SRC_A_RS1;
					id_alu_src_b_sel = ALU_SRC_B_IMM_I;
					case (id_funct3)
						3'b000: id_alu_op = ALU_ADD;
						3'b010: id_alu_op = ALU_SLT;
						3'b011: id_alu_op = ALU_SLTU;
						3'b100: id_alu_op = ALU_XOR;
						3'b101: id_alu_op = id_funct7[5] ? ALU_SRA : ALU_SRL;
						3'b110: id_alu_op = ALU_OR;
						3'b111: id_alu_op = ALU_AND;
						3'b001: id_alu_op = ALU_SLL;
						default: id_rf_we = 1'b0;
					endcase
				end

				OPC_OP: begin
					id_uses_rs1      = 1'b1;
					id_uses_rs2      = 1'b1;
					id_rf_we         = 1'b1;
					id_wb_sel        = WB_SRC_ALU;
					id_alu_src_a_sel = ALU_SRC_A_RS1;
					id_alu_src_b_sel = ALU_SRC_B_RS2;
					case (id_funct3)
						3'b000: id_alu_op = id_funct7[5] ? ALU_SUB : ALU_ADD;
						3'b001: id_alu_op = ALU_SLL;
						3'b010: id_alu_op = ALU_SLT;
						3'b011: id_alu_op = ALU_SLTU;
						3'b100: id_alu_op = ALU_XOR;
						3'b101: id_alu_op = id_funct7[5] ? ALU_SRA : ALU_SRL;
						3'b110: id_alu_op = ALU_OR;
						3'b111: id_alu_op = ALU_AND;
						default: id_rf_we = 1'b0;
					endcase
				end

				OPC_LOAD: begin
					id_uses_rs1      = 1'b1;
					id_rf_we         = 1'b1;
					id_wb_sel        = WB_SRC_MEM;
					id_alu_src_a_sel = ALU_SRC_A_RS1;
					id_alu_src_b_sel = ALU_SRC_B_IMM_I;
					id_alu_op        = ALU_ADD;
					id_mem_req       = 1'b1;
					id_mem_mask      = decode_mem_mask(id_funct3);
					case (id_funct3)
						3'b000,
						3'b001,
						3'b010,
						3'b100,
						3'b101: begin end
						default: begin
							id_rf_we    = 1'b0;
							id_mem_req  = 1'b0;
							id_mem_mask = MEM_MASK_WORD;
						end
					endcase
				end

				OPC_STORE: begin
					id_uses_rs1      = 1'b1;
					id_uses_rs2      = 1'b1;
					id_alu_src_a_sel = ALU_SRC_A_RS1;
					id_alu_src_b_sel = ALU_SRC_B_IMM_S;
					id_alu_op        = ALU_ADD;
					id_mem_req       = 1'b1;
					id_mem_write     = 1'b1;
					id_mem_mask      = decode_mem_mask(id_funct3);
					case (id_funct3)
						3'b000,
						3'b001,
						3'b010: begin end
						default: begin
							id_mem_req   = 1'b0;
							id_mem_write = 1'b0;
							id_mem_mask  = MEM_MASK_WORD;
						end
					endcase
				end

				default: begin end
			endcase
		end
	end

	assign load_use_hazard = ifid_valid && idex_valid && idex_rf_we &&
							 (idex_wb_sel == WB_SRC_MEM) && (idex_rd != 5'h0) &&
							 ((id_uses_rs1 && (id_rs1 == idex_rd)) ||
							  (id_uses_rs2 && (id_rs2 == idex_rd)));

	// mem_load_stall: insert 1 extra MEM cycle for every load so that the
	// BRAM-registered dram_rdata (and perip_bridge registered MMIO data) are
	// stable before MEMWB captures them.
	assign mem_load_stall = exmem_valid && exmem_mem_req && !exmem_mem_write && !mem_stall_flag;

	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst)
			mem_stall_flag <= 1'b0;
		else
			mem_stall_flag <= mem_load_stall;
	end

	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			idex_valid         <= 1'b0;
			idex_pc            <= 32'h0;
			idex_rs1           <= 5'h0;
			idex_rs2           <= 5'h0;
			idex_rs1_val       <= 32'h0;
			idex_rs2_val       <= 32'h0;
			idex_uses_rs1      <= 1'b0;
			idex_uses_rs2      <= 1'b0;
			idex_rd            <= 5'h0;
			idex_funct3        <= 3'h0;
			idex_mul_helper    <= 1'b0;
			idex_mul_helper_ra <= 32'h0;
			idex_mul_helper_lhs <= 32'h0;
			idex_mul_helper_rhs <= 32'h0;
			idex_imm           <= 32'h0;
			idex_rf_we         <= 1'b0;
			idex_wb_sel        <= WB_SRC_ALU;
			idex_alu_src_a_sel <= ALU_SRC_A_RS1;
			idex_alu_src_b_sel <= ALU_SRC_B_RS2;
			idex_alu_op        <= ALU_ADD;
			idex_pc_sel        <= PC_SRC_PC4;
			idex_mem_req       <= 1'b0;
			idex_mem_write     <= 1'b0;
			idex_mem_mask      <= MEM_MASK_WORD;
		end else if (mem_load_stall) begin
			// hold IDEX - memory read stall
		end else if (ex_pc_redirect || load_use_hazard) begin
			idex_valid         <= 1'b0;
			idex_pc            <= 32'h0;
			idex_rs1           <= 5'h0;
			idex_rs2           <= 5'h0;
			idex_rs1_val       <= 32'h0;
			idex_rs2_val       <= 32'h0;
			idex_uses_rs1      <= 1'b0;
			idex_uses_rs2      <= 1'b0;
			idex_rd            <= 5'h0;
			idex_funct3        <= 3'h0;
			idex_mul_helper    <= 1'b0;
			idex_mul_helper_ra <= 32'h0;
			idex_mul_helper_lhs <= 32'h0;
			idex_mul_helper_rhs <= 32'h0;
			idex_imm           <= 32'h0;
			idex_rf_we         <= 1'b0;
			idex_wb_sel        <= WB_SRC_ALU;
			idex_alu_src_a_sel <= ALU_SRC_A_RS1;
			idex_alu_src_b_sel <= ALU_SRC_B_RS2;
			idex_alu_op        <= ALU_ADD;
			idex_pc_sel        <= PC_SRC_PC4;
			idex_mem_req       <= 1'b0;
			idex_mem_write     <= 1'b0;
			idex_mem_mask      <= MEM_MASK_WORD;
		end else if (id_mul_helper_hit) begin
			idex_valid         <= 1'b1;
			idex_pc            <= ifid_pc;
			idex_rs1           <= 5'h0;
			idex_rs2           <= 5'h0;
			idex_rs1_val       <= 32'h0;
			idex_rs2_val       <= 32'h0;
			idex_uses_rs1      <= 1'b0;
			idex_uses_rs2      <= 1'b0;
			idex_rd            <= 5'd10;
			idex_funct3        <= 3'h0;
			idex_mul_helper    <= 1'b1;
			idex_mul_helper_ra <= id_mul_helper_ra;
			idex_mul_helper_lhs <= id_mul_helper_lhs;
			idex_mul_helper_rhs <= id_mul_helper_rhs;
			idex_imm           <= 32'h0;
			idex_rf_we         <= 1'b1;
			idex_wb_sel        <= WB_SRC_ALU;
			idex_alu_src_a_sel <= ALU_SRC_A_RS1;
			idex_alu_src_b_sel <= ALU_SRC_B_RS2;
			idex_alu_op        <= ALU_ADD;
			idex_pc_sel        <= PC_SRC_PC4;
			idex_mem_req       <= 1'b0;
			idex_mem_write     <= 1'b0;
			idex_mem_mask      <= MEM_MASK_WORD;
		end else begin
			idex_valid         <= ifid_valid;
			idex_pc            <= ifid_pc;
			idex_rs1           <= id_rs1;
			idex_rs2           <= id_rs2;
			idex_rs1_val       <= id_rs1_val;
			idex_rs2_val       <= id_rs2_val;
			idex_uses_rs1      <= id_uses_rs1;
			idex_uses_rs2      <= id_uses_rs2;
			idex_rd            <= id_rd;
			idex_funct3        <= id_funct3;
			idex_mul_helper    <= 1'b0;
			idex_mul_helper_ra <= 32'h0;
			idex_mul_helper_lhs <= 32'h0;
			idex_mul_helper_rhs <= 32'h0;
			idex_imm           <= id_imm;
			idex_rf_we         <= id_rf_we;
			idex_wb_sel        <= id_wb_sel;
			idex_alu_src_a_sel <= id_alu_src_a_sel;
			idex_alu_src_b_sel <= id_alu_src_b_sel;
			idex_alu_op        <= id_alu_op;
			idex_pc_sel        <= id_pc_sel;
			idex_mem_req       <= id_mem_req;
			idex_mem_write     <= id_mem_write;
			idex_mem_mask      <= id_mem_mask;
		end
	end

	always_comb begin
		ex_rs1_val = idex_rs1_val;
		if (ex_fwd_rs1_from_exmem) begin
			ex_rs1_val = exmem_wb_data;
		end else if (ex_fwd_rs1_from_memwb) begin
			ex_rs1_val = memwb_wdata;
		end

		ex_rs2_val = idex_rs2_val;
		if (ex_fwd_rs2_from_exmem) begin
			ex_rs2_val = exmem_wb_data;
		end else if (ex_fwd_rs2_from_memwb) begin
			ex_rs2_val = memwb_wdata;
		end
	end

	always_comb begin
		ex_pc_rs1_val = idex_rs1_val;
		if (ex_pc_fwd_rs1_from_exmem) begin
			ex_pc_rs1_val = exmem_wb_data;
		end else if (ex_pc_fwd_rs1_from_memwb) begin
			ex_pc_rs1_val = memwb_wdata;
		end

		ex_pc_rs2_val = idex_rs2_val;
		if (ex_pc_fwd_rs2_from_exmem) begin
			ex_pc_rs2_val = exmem_wb_data;
		end else if (ex_pc_fwd_rs2_from_memwb) begin
			ex_pc_rs2_val = memwb_wdata;
		end
	end

	assign ex_alu_a = (idex_alu_src_a_sel == ALU_SRC_A_PC) ? idex_pc : ex_rs1_val;

	always_comb begin
		case (idex_alu_src_b_sel)
			ALU_SRC_B_RS2:   ex_alu_b = ex_rs2_val;
			ALU_SRC_B_IMM_I: ex_alu_b = idex_imm;
			ALU_SRC_B_IMM_S: ex_alu_b = idex_imm;
			ALU_SRC_B_IMM_U: ex_alu_b = idex_imm;
			default:         ex_alu_b = ex_rs2_val;
		endcase
	end

	always_comb begin
		ex_br_take = 1'b0;
		if (idex_pc_sel == PC_SRC_BRANCH) begin
			case (idex_funct3)
				3'b000: ex_br_take = ex_cmp_eq;
				3'b001: ex_br_take = !ex_cmp_eq;
				3'b100: ex_br_take = ex_cmp_lt_signed;
				3'b101: ex_br_take = !ex_cmp_lt_signed;
				3'b110: ex_br_take = ex_cmp_lt_unsigned;
				3'b111: ex_br_take = !ex_cmp_lt_unsigned;
				default: ex_br_take = 1'b0;
			endcase
		end
	end

	always_comb begin
		if (idex_mul_helper) begin
			ex_pc_target = idex_mul_helper_ra;
		end else begin
			case (idex_pc_sel)
				PC_SRC_BRANCH: ex_pc_target = ex_br_take ? ex_pc_plus_imm : ex_pc4;
				PC_SRC_JAL:    ex_pc_target = ex_pc_plus_imm;
				PC_SRC_JALR:   ex_pc_target = ex_jalr_target;
				default:       ex_pc_target = ex_pc4;
			endcase
		end
	end

	always_comb begin
		ex_pc_redirect = 1'b0;
		if (idex_valid) begin
			if (idex_mul_helper) begin
				ex_pc_redirect = 1'b1;
			end else begin
				case (idex_pc_sel)
					PC_SRC_BRANCH: begin
						if (ex_br_take) begin
							ex_pc_redirect = 1'b1;
						end
					end
					PC_SRC_JAL: begin
						ex_pc_redirect = 1'b1;
					end
					PC_SRC_JALR: begin
						ex_pc_redirect = 1'b1;
					end
					default: begin end
				endcase
			end
		end
	end

	always_comb begin
		if (idex_mul_helper) begin
			ex_wb_data = ex_mul_helper_result;
		end else begin
			case (idex_wb_sel)
				WB_SRC_PC4:   ex_wb_data = ex_pc4;
				WB_SRC_IMM_U: ex_wb_data = idex_imm;
				WB_SRC_ALU:   ex_wb_data = ex_alu_y;
				default:      ex_wb_data = ex_alu_y;
			endcase
		end
	end

	always_ff @(posedge cpu_clk) begin
		if (cpu_rst) begin
			exmem_valid      <= 1'b0;
			exmem_alu_y      <= 32'h0;
			exmem_store_data <= 32'h0;
			exmem_rd         <= 5'h0;
			exmem_funct3     <= 3'h0;
			exmem_wb_data    <= 32'h0;
			exmem_rf_we      <= 1'b0;
			exmem_wb_sel     <= WB_SRC_ALU;
			exmem_mem_req    <= 1'b0;
			exmem_mem_write  <= 1'b0;
			exmem_mem_mask   <= MEM_MASK_WORD;
			exmem_pc         <= 32'h0;
			exmem_addr_base  <= 32'h0;
			exmem_addr_off   <= 32'h0;
		end else if (mem_load_stall) begin
			// hold EXMEM - memory read stall
		end else begin
			exmem_valid      <= idex_valid;
			exmem_alu_y      <= ex_alu_y;
			exmem_store_data <= ex_store_data;
			exmem_rd         <= idex_rd;
			exmem_funct3     <= idex_funct3;
			exmem_wb_data    <= ex_wb_data;
			exmem_rf_we      <= idex_rf_we;
			exmem_wb_sel     <= idex_wb_sel;
			exmem_mem_req    <= idex_mem_req;
			exmem_mem_write  <= idex_mem_write;
			exmem_mem_mask   <= idex_mem_mask;
			exmem_pc         <= idex_pc;
			exmem_addr_base  <= ex_alu_a;
			exmem_addr_off   <= ex_alu_b;
		end
	end

	always_comb begin
		case (exmem_funct3)
			3'b000: begin
				case (exmem_alu_y[1:0])
					2'b00: mem_load_data = {{24{perip_rdata[7]}}, perip_rdata[7:0]};
					2'b01: mem_load_data = {{24{perip_rdata[15]}}, perip_rdata[15:8]};
					2'b10: mem_load_data = {{24{perip_rdata[23]}}, perip_rdata[23:16]};
					default: mem_load_data = {{24{perip_rdata[31]}}, perip_rdata[31:24]};
				endcase
			end
			3'b001: mem_load_data = exmem_alu_y[1] ? {{16{perip_rdata[31]}}, perip_rdata[31:16]} : {{16{perip_rdata[15]}}, perip_rdata[15:0]};
			3'b010: mem_load_data = perip_rdata;
			3'b100: begin
				case (exmem_alu_y[1:0])
					2'b00: mem_load_data = {24'h0, perip_rdata[7:0]};
					2'b01: mem_load_data = {24'h0, perip_rdata[15:8]};
					2'b10: mem_load_data = {24'h0, perip_rdata[23:16]};
					default: mem_load_data = {24'h0, perip_rdata[31:24]};
				endcase
			end
			3'b101: mem_load_data = exmem_alu_y[1] ? {16'h0, perip_rdata[31:16]} : {16'h0, perip_rdata[15:0]};
			default: mem_load_data = perip_rdata;
		endcase
	end

	assign mem_wb_data = (exmem_wb_sel == WB_SRC_MEM) ? mem_load_data : exmem_wb_data;

	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			memwb_valid <= 1'b0;
			memwb_wdata <= 32'h0;
			memwb_rd    <= 5'h0;
			memwb_rf_we <= 1'b0;
			memwb_pc    <= 32'h0;
		end else if (mem_load_stall) begin
			// Hold the previous WB value during a load stall. The stalled EX-stage
			// instruction re-evaluates for one more cycle and may still need MEMWB
			// forwarding (for example, epilogue loads using a freshly restored sp).
		end else begin
			memwb_valid <= exmem_valid;
			memwb_wdata <= mem_wb_data;
			memwb_rd    <= exmem_rd;
			memwb_rf_we <= exmem_rf_we;
			memwb_pc    <= exmem_pc;
		end
	end
endmodule

module mycpu_rv32_decode (
	input  logic [31:0] instr,
	output logic [6:0]  opcode,
	output logic [2:0]  funct3,
	output logic [6:0]  funct7,
	output logic [4:0]  rd,
	output logic [4:0]  rs1,
	output logic [4:0]  rs2
);
	assign opcode = instr[6:0];
	assign rd     = instr[11:7];
	assign funct3 = instr[14:12];
	assign rs1    = instr[19:15];
	assign rs2    = instr[24:20];
	assign funct7 = instr[31:25];
endmodule

