`timescale 1ns / 1ps

module tb_csr_min;
	// 最小 CSR 回归：
	// 1. CSRRW 写 mtvec，并验证读回旧值/新值；
	// 2. ECALL 进入 trap，验证 mepc / mcause / mstatus 更新；
	// 3. 在 trap handler 内修改 mepc，再通过 MRET 返回；
	// 4. 返回后再次读取 CSR，确认写回与 trap/return 语义正确。

	localparam realtime CPU_CLK_HALF_PERIOD = 2.5;
	localparam logic [31:0] RESET_PC        = 32'h8000_0000;
	localparam logic [31:0] MTVEC_TARGET    = 32'h8000_0040;
	localparam int IROM_DEPTH               = 256;

	logic        cpu_clk;
	logic        cpu_rst;
	logic [11:0] irom_addr;
	logic [31:0] irom_data;
	logic [31:0] perip_addr;
	logic        perip_wen;
	logic [1:0]  perip_mask;
	logic [31:0] perip_wdata;
	logic [31:0] perip_rdata;

	logic [31:0] imem [0:IROM_DEPTH-1];
	integer cycle_count;
	integer settle_cycles;

	myCPU dut (
		.cpu_rst    (cpu_rst),
		.cpu_clk    (cpu_clk),
		.irom_addr  (irom_addr),
		.irom_data  (irom_data),
		.perip_addr (perip_addr),
		.perip_wen  (perip_wen),
		.perip_mask (perip_mask),
		.perip_wdata(perip_wdata),
		.perip_rdata(perip_rdata)
	);

	function automatic logic [31:0] enc_i(
		input int imm,
		input int rs1,
		input logic [2:0] funct3,
		input int rd,
		input logic [6:0] opcode
	);
		logic [11:0] imm12;
		begin
			imm12 = imm[11:0];
			enc_i = {imm12, rs1[4:0], funct3, rd[4:0], opcode};
		end
	endfunction

	function automatic logic [31:0] enc_u(
		input int imm20,
		input int rd,
		input logic [6:0] opcode
	);
		begin
			enc_u = {imm20[19:0], rd[4:0], opcode};
		end
	endfunction

	function automatic logic [31:0] enc_b(
		input int imm,
		input int rs2,
		input int rs1,
		input logic [2:0] funct3
	);
		logic [12:0] imm13;
		begin
			imm13 = imm[12:0];
			enc_b = {
				imm13[12],
				imm13[10:5],
				rs2[4:0],
				rs1[4:0],
				funct3,
				imm13[4:1],
				imm13[11],
				7'b1100011
			};
		end
	endfunction

	function automatic logic [31:0] enc_csr(
		input logic [11:0] csr,
		input int rs1_uimm,
		input logic [2:0] funct3,
		input int rd
	);
		begin
			enc_csr = {csr, rs1_uimm[4:0], funct3, rd[4:0], 7'b1110011};
		end
	endfunction

	initial begin
		cpu_clk = 1'b0;
		forever #CPU_CLK_HALF_PERIOD cpu_clk = ~cpu_clk;
	end

	assign irom_data   = imem[irom_addr];
	assign perip_rdata = 32'h0;

	initial begin
		integer idx;

		cpu_rst   = 1'b1;

		for (idx = 0; idx < IROM_DEPTH; idx = idx + 1) begin
			imem[idx] = enc_i(0, 0, 3'b000, 0, 7'b0010011); // nop
		end

		// 0x8000_0000: x1 = 0x8000_0040
		imem[0]  = enc_u(20'h80000, 1, 7'b0110111);           // lui  x1, 0x80000
		imem[1]  = enc_i(64, 1, 3'b000, 1, 7'b0010011);       // addi x1, x1, 64
		// mtvec = x1, x2 <- old mtvec(0)
		imem[2]  = enc_csr(12'h305, 1, 3'b001, 2);            // csrrw x2, mtvec, x1
		// x3 <- mtvec
		imem[3]  = enc_csr(12'h305, 0, 3'b010, 3);            // csrrs x3, mtvec, x0
		// 触发 ecall，期望跳到 0x8000_0040
		imem[4]  = 32'h0000_0073;                             // ecall
		// 返回后读取 mepc/mcause/mstatus
		imem[5]  = enc_csr(12'h341, 0, 3'b010, 7);            // csrrs x7, mepc, x0
		imem[6]  = enc_csr(12'h342, 0, 3'b010, 8);            // csrrs x8, mcause, x0
		imem[7]  = enc_csr(12'h300, 0, 3'b010, 9);            // csrrs x9, mstatus, x0
		imem[8]  = enc_b(0, 0, 0, 3'b000);                    // beq x0, x0, 0

		// 0x8000_0040 trap handler
		imem[16] = enc_csr(12'h341, 0, 3'b010, 4);            // csrrs x4, mepc, x0
		imem[17] = enc_i(4, 4, 3'b000, 4, 7'b0010011);        // addi  x4, x4, 4
		imem[18] = enc_csr(12'h341, 4, 3'b001, 0);            // csrrw x0, mepc, x4
		imem[19] = enc_csr(12'h342, 0, 3'b010, 5);            // csrrs x5, mcause, x0
		imem[20] = enc_csr(12'h300, 0, 3'b010, 6);            // csrrs x6, mstatus, x0
		imem[21] = 32'h3020_0073;                             // mret

		repeat (10) @(posedge cpu_clk);
		cpu_rst = 1'b0;
		$display("[CSR-MIN] Reset released.");
	end

	always_ff @(posedge cpu_clk) begin
		if (cpu_rst) begin
			cycle_count <= 0;
			settle_cycles <= -1;
		end else begin
			cycle_count <= cycle_count + 1;
			if (settle_cycles > 0) begin
				settle_cycles <= settle_cycles - 1;
			end else if ((settle_cycles == -1) && (dut.pc_q == (RESET_PC + 32'd32))) begin
				// 进入主线末尾自旋后，再额外等几拍，让 x7/x8/x9 的 CSR 读回真正完成写回。
				settle_cycles <= 6;
			end
		end
	end

	// 当程序回到主线并进入自旋时，检查 CSR 语义是否符合预期。
	always_ff @(posedge cpu_clk) begin
		if (!cpu_rst) begin
			if (settle_cycles == 0) begin
				if (dut.u_rf.reg_bank[2] !== 32'h0000_0000) begin
					$error("[CSR-MIN] x2(old mtvec) mismatch: %h", dut.u_rf.reg_bank[2]);
				end
				if (dut.u_rf.reg_bank[3] !== MTVEC_TARGET) begin
					$error("[CSR-MIN] x3(read mtvec) mismatch: %h", dut.u_rf.reg_bank[3]);
				end
				if (dut.u_rf.reg_bank[4] !== (RESET_PC + 32'd20)) begin
					$error("[CSR-MIN] x4(updated mepc) mismatch: %h", dut.u_rf.reg_bank[4]);
				end
				if (dut.u_rf.reg_bank[5] !== 32'd11) begin
					$error("[CSR-MIN] x5(mcause in trap) mismatch: %h", dut.u_rf.reg_bank[5]);
				end
				if (dut.u_rf.reg_bank[6] !== 32'h0000_1800) begin
					$error("[CSR-MIN] x6(mstatus in trap) mismatch: %h", dut.u_rf.reg_bank[6]);
				end
				if (dut.u_rf.reg_bank[7] !== (RESET_PC + 32'd20)) begin
					$error("[CSR-MIN] x7(mepc after mret) mismatch: %h", dut.u_rf.reg_bank[7]);
				end
				if (dut.u_rf.reg_bank[8] !== 32'd11) begin
					$error("[CSR-MIN] x8(mcause after mret) mismatch: %h", dut.u_rf.reg_bank[8]);
				end
				if (dut.u_rf.reg_bank[9] !== 32'h0000_0080) begin
					$error("[CSR-MIN] x9(mstatus after mret) mismatch: %h", dut.u_rf.reg_bank[9]);
				end
				if (dut.csr_mtvec !== MTVEC_TARGET) begin
					$error("[CSR-MIN] csr_mtvec mismatch: %h", dut.csr_mtvec);
				end
				if (dut.csr_mepc !== (RESET_PC + 32'd20)) begin
					$error("[CSR-MIN] csr_mepc mismatch: %h", dut.csr_mepc);
				end
				if (dut.csr_mcause !== 32'd11) begin
					$error("[CSR-MIN] csr_mcause mismatch: %h", dut.csr_mcause);
				end
				if (dut.csr_mstatus !== 32'h0000_0080) begin
					$error("[CSR-MIN] csr_mstatus mismatch: %h", dut.csr_mstatus);
				end
				$display("[CSR-MIN] PASS at cycle %0d", cycle_count);
				$finish;
			end

			if (cycle_count > 300) begin
				$error("[CSR-MIN] TIMEOUT pc=%h x3=%h x4=%h x5=%h x6=%h x7=%h x8=%h x9=%h",
					dut.pc_q,
					dut.u_rf.reg_bank[3],
					dut.u_rf.reg_bank[4],
					dut.u_rf.reg_bank[5],
					dut.u_rf.reg_bank[6],
					dut.u_rf.reg_bank[7],
					dut.u_rf.reg_bank[8],
					dut.u_rf.reg_bank[9]);
				$finish;
			end
		end
	end

endmodule