module CSR #(
    parameter   DATAWIDTH = 32	
)(
	input  logic 					clk			,
	input  logic 					rst			,
	input  logic [DATAWIDTH-1:0]	pc			,
	input  logic [DATAWIDTH-1:0]	rf1			,
	input  logic [11:0] 			csr_idx		,
	input  logic [3:0]  			CSRControll	,

	output logic [DATAWIDTH-1:0] 	csr_npc		,
	output logic [DATAWIDTH-1:0]	csr_wb
);
	// 一个简化版 CSR 子系统，仅实现当前工程需要的少量 M-mode CSR：
	// - mstatus / mtvec / mepc / mcause
	// - csrrs / csrrw / csrrc
	// - ecall / mret
	localparam logic [11:0] CSR_MSTATUS = 12'h300;
	localparam logic [11:0] CSR_MTVEC   = 12'h305;
	localparam logic [11:0] CSR_MEPC    = 12'h341;
	localparam logic [11:0] CSR_MCAUSE  = 12'h342;

	localparam logic [3:0] CSR_CTL_CSRRS = 4'b0001;
	localparam logic [3:0] CSR_CTL_CSRRW = 4'b0010;
	localparam logic [3:0] CSR_CTL_CSRRC = 4'b0011;
	localparam logic [3:0] CSR_CTL_ECALL = 4'b0100;
	localparam logic [3:0] CSR_CTL_MRET  = 4'b1000;

	localparam logic [DATAWIDTH-1:0] CSR_WRITE_MASK = {DATAWIDTH{1'b1}};

	logic [DATAWIDTH-1:0] mstatus;
	logic [DATAWIDTH-1:0] mepc;
	logic [DATAWIDTH-1:0] mtvec;
	logic [DATAWIDTH-1:0] mcause;
	logic [DATAWIDTH-1:0] csr_rdata;

	always_ff @(posedge clk or posedge rst) begin
		if (rst) begin
			mstatus <= 32'h1800;
			mtvec   <= 32'h0;
			mepc    <= 32'h0;
			mcause  <= 32'h0;
		end else begin
			unique case (CSRControll)
				CSR_CTL_CSRRS: begin
					unique case (csr_idx)
						CSR_MSTATUS: mstatus <= CSR_WRITE_MASK & (mstatus | rf1);
						CSR_MTVEC:   mtvec   <= mtvec | rf1;
						CSR_MEPC:    mepc    <= mepc | rf1;
						CSR_MCAUSE:  mcause  <= mcause | rf1;
						default: begin end
					endcase
				end

				CSR_CTL_CSRRW: begin
					unique case (csr_idx)
						CSR_MSTATUS: mstatus <= CSR_WRITE_MASK & rf1;
						CSR_MTVEC:   mtvec   <= rf1;
						CSR_MEPC:    mepc    <= rf1;
						CSR_MCAUSE:  mcause  <= rf1;
						default: begin end
					endcase
				end

				CSR_CTL_CSRRC: begin
					unique case (csr_idx)
						CSR_MSTATUS: mstatus <= CSR_WRITE_MASK & (mstatus & ~rf1);
						CSR_MTVEC:   mtvec   <= mtvec & ~rf1;
						CSR_MEPC:    mepc    <= mepc & ~rf1;
						CSR_MCAUSE:  mcause  <= mcause & ~rf1;
						default: begin end
					endcase
				end

				CSR_CTL_ECALL: begin
					mstatus <= {mstatus[31:13], 2'b11, mstatus[10:8], mstatus[3],
								mstatus[6:4], 1'b0, mstatus[2:0]};
					mepc    <= pc;
					mcause  <= 32'h0b;
				end

				CSR_CTL_MRET: begin
					mstatus <= {mstatus[31:13], 2'b00, mstatus[10:8], 1'b1,
								mstatus[6:4], mstatus[7], mstatus[2:0]};
				end

				default: begin end
			endcase
		end
	end

	always_comb begin
		unique case (csr_idx)
			CSR_MSTATUS: csr_rdata = mstatus;
			CSR_MTVEC:   csr_rdata = mtvec;
			CSR_MEPC:    csr_rdata = mepc;
			CSR_MCAUSE:  csr_rdata = mcause;
			default:     csr_rdata = 32'h0;
		endcase
	end

	assign csr_wb = csr_rdata;
	assign csr_npc = (CSRControll == CSR_CTL_ECALL) ? mtvec :
					 (CSRControll == CSR_CTL_MRET)  ? mepc :
					 32'h0;
	
	
endmodule
