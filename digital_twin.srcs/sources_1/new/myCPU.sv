`timescale 1ns / 1ps

module myCPU #(
	parameter ENABLE_MUL_HELPER_ACCEL = 1'b0
) (
	input  logic         cpu_rst,
	input  logic         cpu_clk,

	output logic [11:0]  irom_addr,
	output logic         irom_en,
	input  logic [31:0]  irom_data,

	output logic [31:0]  perip_addr,
	output logic         perip_wen,
	output logic [1:0]   perip_mask,
	output logic [3:0]   perip_wstrb,
	output logic [31:0]  perip_wdata,
	input  logic [31:0]  perip_rdata
);
	// 这个 CPU 是一个面向 RV32I 子集的简化流水实现。
	// 顶层接口只暴露两类总线：
	// 1. 指令只读口：给 IROM 地址，取回 32bit 指令。
	// 2. 外设/数据口：统一访问 DRAM、计数器和 MMIO。

	// 复位后从固定 Boot 地址开始执行。
	localparam logic [31:0] RESET_PC      = 32'h8000_0000;// 重置 PC 地址
	// NOP 采用 addi x0, x0, 0。
	localparam logic [31:0] NOP_INSTR     = 32'h0000_0013;// NOP 指令
	// mul helper 相关地址用于识别“乘法辅助例程入口”和它可能的返回点。
	localparam logic [31:0] MUL_HELPER_PC = 32'h8000_1fa8;// mul helper 入口地址
	localparam logic [31:0] MUL_HELPER_LOOP004_RA = 32'h8000_04c8;// mul helper 循环004返回地址
	localparam logic [31:0] MUL_HELPER_LOOP006_RA = 32'h8000_0734;// mul helper 循环006返回地址

	// RV32I 基本 opcode 编码。
	localparam logic [6:0]  OPC_LUI       = 7'b0110111; // LUI 指令，主要负责加载高 20 位立即数到寄存器。
	localparam logic [6:0]  OPC_AUIPC     = 7'b0010111; // AUIPC 指令，用于将当前 PC 加上一个立即数并存储到寄存器中，常用于生成 PC 相对地址。
	localparam logic [6:0]  OPC_JAL       = 7'b1101111; // JAL 指令，用于无条件跳转并保存返回地址。
	localparam logic [6:0]  OPC_JALR      = 7'b1100111; // JALR 指令，用于寄存器间接跳转并保存返回地址。
	localparam logic [6:0]  OPC_BRANCH    = 7'b1100011; // 分支指令，用于条件跳转。
	localparam logic [6:0]  OPC_LOAD      = 7'b0000011; // 加载指令，用于从内存读取数据。
	localparam logic [6:0]  OPC_STORE     = 7'b0100011; // 存储指令，用于向内存写入数据。
	localparam logic [6:0]  OPC_OPIMM     = 7'b0010011; // 立即数操作指令，用于对寄存器和立即数进行算术或逻辑操作。
	localparam logic [6:0]  OPC_OP        = 7'b0110011; // 寄存器操作指令，用于对两个寄存器进行算术或逻辑操作。
	localparam logic [6:0]  OPC_SYSTEM    = 7'b1110011; // 系统指令，用于特权操作和环境调用。

	// ALU 控制码。
	localparam logic [3:0]  ALU_ADD       = 4'd0;// ALU 执行加法操作。
	localparam logic [3:0]  ALU_SUB       = 4'd1;// ALU 执行减法操作。
	localparam logic [3:0]  ALU_AND       = 4'd2;// ALU 执行按位与操作。
	localparam logic [3:0]  ALU_OR        = 4'd3;// ALU 执行按位或操作。
	localparam logic [3:0]  ALU_XOR       = 4'd4;// ALU 执行按位异或操作。
	localparam logic [3:0]  ALU_SLT       = 4'd5;// ALU 执行有符号小于比较操作。
	localparam logic [3:0]  ALU_SLTU      = 4'd6;// ALU 执行无符号小于比较操作。
	localparam logic [3:0]  ALU_SLL       = 4'd7;// ALU 执行逻辑左移操作。
	localparam logic [3:0]  ALU_SRL       = 4'd8;// ALU 执行逻辑右移操作。
	localparam logic [3:0]  ALU_SRA       = 4'd9;// ALU 执行算术右移操作。

	// ALU A 端输入来源：rs1 或 PC。
	localparam logic        ALU_SRC_A_RS1 = 1'b0;// ALU A 端输入来自寄存器 rs1。
	localparam logic        ALU_SRC_A_PC  = 1'b1;// ALU A 端输入来自当前 PC。

	// ALU B 端输入来源：rs2 / I-type 立即数 / S-type 立即数 / U-type 立即数。
	localparam logic [1:0]  ALU_SRC_B_RS2   = 2'd0;// ALU B 端输入来自寄存器 rs2。
	localparam logic [1:0]  ALU_SRC_B_IMM_I = 2'd1;// ALU B 端输入来自 I 型立即数。
	localparam logic [1:0]  ALU_SRC_B_IMM_S = 2'd2;// ALU B 端输入来自 S 型立即数。
	localparam logic [1:0]  ALU_SRC_B_IMM_U = 2'd3;// ALU B 端输入来自 U 型立即数。

	// Z 轻量级指令扩展操作码。
	localparam logic [5:0]  ZOP_ANDN     = 6'd0;// Z 轻量级指令操作码 ANDN，表示按位与非操作。
	localparam logic [5:0]  ZOP_ORN      = 6'd1;// Z 轻量级指令操作码 ORN，表示按位或非操作。
	localparam logic [5:0]  ZOP_XNOR     = 6'd2;// Z 轻量级指令操作码 XNOR，表示按位异或非操作。
	localparam logic [5:0]  ZOP_SEXTB	 = 6'd3;// Z 轻量级指令操作码 SEXTB，表示符号扩展字节操作
	localparam logic [5:0]  ZOP_SEXTH	 = 6'd4;// Z 轻量级指令操作码 SEXTB，表示符号扩展半字操作
	localparam logic [5:0]  ZOP_ZEXTH	 = 6'd5;// Z 轻量级指令操作码 ZEXTH，表示零扩展半字操作
	localparam logic [5:0]  ZOP_ORCB	 = 6'd6;// Z 轻量级指令操作码 ORCB，表示按位或字节操作
	localparam logic [5:0]  ZOP_PACK	 = 6'd7;// Z 轻量级指令操作码 PACK，表示打包操作
	localparam logic [5:0]  ZOP_PACKH	 = 6'd8;// Z 轻量级指令操作码 PACKH，表示打包高半字操作
	localparam logic [5:0]  ZOP_REV8	 = 6'd9;// Z 轻量级指令操作码 REV8，表示按字节反转操作
	localparam logic [5:0]  ZOP_BREV8	 = 6'd10;// Z 轻量级指令操作码 BREV8，表示按字节反转操作
	localparam logic [5:0]  ZOP_ZIP	     = 6'd11;// Z 轻量级指令操作码 ZIP，表示压缩操作
	localparam logic [5:0]  ZOP_UNZIP	 = 6'd12;// Z 轻量级指令操作码 UNZIP，表示解压操作
	localparam logic [5:0]  ZOP_BCLR     = 6'd13;// Z 轻量级指令操作码 BCLR，表示按位清零操作
	localparam logic [5:0]  ZOP_BCLRI    = 6'd14;// Z 轻量级指令操作码 BCLRI，表示按位清零立即数操作
	localparam logic [5:0]  ZOP_BEXT	 = 6'd15;// Z 轻量级指令操作码 BEXT，表示按位提取操作
	localparam logic [5:0]  ZOP_BEXTI	 = 6'd16;// Z 轻量级指令操作码 BEXTI，表示按位提取立即数操作
	localparam logic [5:0]  ZOP_BINV	 = 6'd17;// Z 轻量级指令操作码 BINV，表示按位取反操作
	localparam logic [5:0]  ZOP_BINVI	 = 6'd18;// Z 轻量级指令操作码 BINVI，表示按位取反立即数操作
	localparam logic [5:0]  ZOP_BSET	 = 6'd19;// Z 轻量级指令操作码 BSET，表示按位设置操作
	localparam logic [5:0]  ZOP_BSETI	 = 6'd20;// Z 轻量级指令操作码 BSETI，表示按位设置立即数操作
	localparam logic [5:0]  ZOP_SH1ADD   = 6'd21;// Z_B_SMALL sh1add。
	localparam logic [5:0]  ZOP_SH2ADD   = 6'd22;// Z_B_SMALL sh2add。
	localparam logic [5:0]  ZOP_SH3ADD   = 6'd23;// Z_B_SMALL sh3add。
	localparam logic [5:0]  ZOP_MIN      = 6'd24;// Z_B_SMALL min。
	localparam logic [5:0]  ZOP_MINU     = 6'd25;// Z_B_SMALL minu。
	localparam logic [5:0]  ZOP_MAX      = 6'd26;// Z_B_SMALL max。
	localparam logic [5:0]  ZOP_MAXU     = 6'd27;// Z_B_SMALL maxu。
	localparam logic [5:0]  ZOP_ROL      = 6'd28;// Z_B_SMALL rol。
	localparam logic [5:0]  ZOP_ROR      = 6'd29;// Z_B_SMALL ror。
	localparam logic [5:0]  ZOP_RORI     = 6'd30;// Z_B_SMALL rori。
	localparam logic [5:0]  ZOP_NONE     = 6'd63;// Z 轻量级指令操作码 NONE，表示没有 Z 轻量级指令操作。

`ifdef ENABLE_Z_B_SMALL
	localparam logic        CPU_ENABLE_Z_B_SMALL = 1'b1;
`else
	localparam logic        CPU_ENABLE_Z_B_SMALL = 1'b0;
`endif

	// WB 选择：ALU 结果、内存返回、PC+4 或 U 型立即数。
	localparam logic [2:0]  WB_SRC_ALU    = 3'd0;// 写回数据选择 ALU 结果。
	localparam logic [2:0]  WB_SRC_MEM    = 3'd1;// 写回数据选择内存返回数据。
	localparam logic [2:0]  WB_SRC_PC4    = 3'd2;// 写回数据选择 PC + 4。
	localparam logic [2:0]  WB_SRC_IMM_U  = 3'd3;// 写回数据选择 U 型立即数。
	localparam logic [2:0]  WB_SRC_CSR    = 3'd4;// 写回数据选择 CSR 寄存器值。
	localparam logic [2:0]  WB_SRC_Z      = 3'd5;// 写回数据选择 Z 轻量级指令结果。

	// PC 下一拍来源。
	localparam logic [1:0]  PC_SRC_PC4    = 2'd0;// PC 下一拍选择 PC + 4。
	localparam logic [1:0]  PC_SRC_BRANCH = 2'd1;// PC 下一拍选择分支目标地址。
	localparam logic [1:0]  PC_SRC_JAL    = 2'd2;// PC 下一拍选择 JAL 指令目标地址。
	localparam logic [1:0]  PC_SRC_JALR   = 2'd3;// PC 下一拍选择 JALR 指令目标地址。

	// 数据口写掩码：字节 / 半字 / 整字。
	localparam logic [1:0]  MEM_MASK_BYTE = 2'b00;// 数据口写掩码选择字节。
	localparam logic [1:0]  MEM_MASK_HALF = 2'b01;// 数据口写掩码选择半字。
	localparam logic [1:0]  MEM_MASK_WORD = 2'b10;// 数据口写掩码选择整字。
	// 0x8010_0000--0x8013_FFFF 是 256 KiB 对齐的 DRAM 区域。
	localparam logic [13:0] DRAM_REGION_TAG = 14'h2004;

	//CSR地址常量
	localparam logic [11:0] CSR_MSTATUS = 12'h300;// CSR 寄存器 MSTATUS 地址，用于保存处理器状态。
	localparam logic [11:0] CSR_MTVEC   = 12'h305;// CSR 寄存器 MTVEC 地址，用于保存异常向量基地址。
	localparam logic [11:0] CSR_MEPC    = 12'h341;// CSR 寄存器 MEPC 地址，用于保存异常返回地址。
	localparam logic [11:0] CSR_MCAUSE  = 12'h342;// CSR 寄存器 MCAUSE 地址，用于保存异常原因。
	localparam logic [11:0] CSR_MSCRATCH = 12'h340;// CSR 寄存器 MSCRATCH 地址，用于保存临时数据。

	//CSR指令类型
	localparam logic [2:0] CSR_OP_NONE  = 3'd0;// CSR 操作类型 NONE，表示没有 CSR 操作。
	localparam logic [2:0] CSR_OP_CSRRW = 3'd1;// CSR 操作类型 CSRRW，表示读写 CSR。
	localparam logic [2:0] CSR_OP_CSRRS = 3'd2;// CSR 操作类型 CSRRS，表示读置位 CSR。
	localparam logic [2:0] CSR_OP_CSRRC = 3'd3;// CSR 操作类型 CSRRC，表示读清除 CSR。
	localparam logic [2:0] CSR_OP_ECALL = 3'd4;// CSR 操作类型 ECALL，表示环境调用。
	localparam logic [2:0] CSR_OP_MRET  = 3'd5;// CSR 操作类型 MRET，表示从机器模式返回。

	//M指令类型
	localparam logic [3:0] M_OP_NONE   = 4'd0;// M 指令类型 NONE，表示没有 M 扩展操作。
	localparam logic [3:0] M_OP_MUL    = 4'd1;// M 指令类型 MUL，表示乘法操作。
	localparam logic [3:0] M_OP_MULH   = 4'd2;// M 指令类型 MULH，表示有符号乘法高位操作。
	localparam logic [3:0] M_OP_MULHSU = 4'd3;// M 指令类型 MULHSU，表示有符号乘法高位操作（混合符号）。
	localparam logic [3:0] M_OP_MULHU  = 4'd4;// M 指令类型 MULHU，表示无符号乘法高位操作。
	localparam logic [3:0] M_OP_DIV    = 4'd5;// M 指令类型 DIV，表示有符号除法操作。
	localparam logic [3:0] M_OP_DIVU   = 4'd6;// M 指令类型 DIVU，表示无符号除法操作。
	localparam logic [3:0] M_OP_REM    = 4'd7;// M 指令类型 REM，表示有符号取模操作。
	localparam logic [3:0] M_OP_REMU   = 4'd8;// M 指令类型 REMU，表示无符号取模操作。

	localparam logic [1:0] LOAD_WAIT_CYCLES = 2'd2;// LOAD 指令等待周期数。

	// =========================
	// IF 级与 IF/ID 流水寄存器 表示取指令阶段的 PC、指令和有效位。
	// =========================
	// 板级 ILA 抓跑飞时只保留少量控制面探针，避免拖累 200MHz 路径。
	logic [31:0] pc_q;      // 当前 PC 寄存器，表示当前正在执行的指令的地址。
	logic [31:0] pc_next;   // 下一拍 PC 值，表示下一条指令的地址。
	logic [31:0] fetch_pc_q;    // 同步 IROM 当前返回指令所对应的请求 PC。
	logic        fetch_valid; // 同步 IROM 当前返回指令是否有效。
	logic [31:0] fetch_hold_pc;
	logic [31:0] fetch_hold_instr;
	logic        fetch_hold_valid;
	logic        fetch_hold_full;
	logic        fetch_stall;   // 前端暂停，同时冻结 PC、IROM 和 IF/ID。

	logic [31:0] ifid_pc;    // IF/ID 流水寄存器中的 PC 值，表示取指阶段的指令地址。
	logic [31:0] ifid_instr; // IF/ID 流水寄存器中的指令值，表示取指阶段的指令内容。
	logic        ifid_valid; // IF/ID 流水寄存器中的有效位，表示取指阶段的指令是否有效。

	// =========================
	// ID 级译码与冒险检测 表示译码阶段的指令字段、立即数、寄存器值和控制信号。
	// =========================
	logic [6:0]  id_opcode; // 译码阶段的指令操作码，表示当前指令的类型。
	logic [6:0]  id_funct7; // 译码阶段的指令功能码7位，表示当前指令的具体操作。
	logic [2:0]  id_funct3; // 译码阶段的指令功能码3位，表示当前指令的具体操作。
	logic [4:0]  id_rd;     // 译码阶段的目标寄存器地址，表示当前指令的写回寄存器。
	logic [4:0]  id_rs1;    // 译码阶段的源寄存器1地址，表示当前指令的第一个操作数寄存器。
	logic [4:0]  id_rs2;    // 译码阶段的源寄存器2地址，表示当前指令的第二个操作数寄存器。
	logic [31:0] id_imm_raw;// 译码阶段的原始立即数，表示当前指令的立即数值。
	logic [31:0] id_imm;    // 译码阶段的立即数，表示当前指令的立即数值。
	logic [31:0] id_rs1_val;// 译码阶段的源寄存器1值，表示当前指令的第一个操作数值。
	logic [31:0] id_rs2_val;// 译码阶段的源寄存器2值，表示当前指令的第二个操作数值。
	logic [31:0] rf_rs1_raw;// 译码阶段的源寄存器1原始值，表示当前指令的第一个操作数原始值。
	logic [31:0] rf_rs2_raw;// 译码阶段的源寄存器2原始值，表示当前指令的第二个操作数原始值。
	logic [31:0] rf_x1_raw; // 译码阶段的寄存器 x1 原始值，表示当前指令的寄存器 x1 的原始值。
	logic [31:0] rf_x10_raw;// 译码阶段的寄存器 x10 原始值，表示当前指令的寄存器 x10 的原始值。
	logic [31:0] rf_x11_raw;// 译码阶段的寄存器 x11 原始值，表示当前指令的寄存器 x11 的原始值。
	logic        id_uses_rs1;// 译码阶段是否使用源寄存器1，表示当前指令是否使用源寄存器1。
	logic        id_uses_rs2;// 译码阶段是否使用源寄存器2，表示当前指令是否使用源寄存器2。
	logic        hazard_uses_rs1; // 仅供冒险判断使用的轻量级源寄存器译码。
	logic        hazard_uses_rs2;
	logic        hazard_is_branch;
	logic        hazard_is_jalr;
	logic        load_use_ex1_hazard;// 译码阶段是否存在 load-use 冒险，表示当前指令是否依赖于前一条 load 指令的结果。
	logic        load_use_hazard;
	logic        load_use_ex2_hazard;
	logic        slow_result_ex1_hazard;
	logic        m_issue_hazard;
	logic        id_fwd_rs1_from_wb;
	logic        id_fwd_rs2_from_wb;
	logic        pc_ex1_hazard;// 译码阶段是否存在 PC 与 EX 阶段的冒险，表示当前指令是否与 EX 阶段的指令存在数据依赖。
	logic        pc_ex2_hazard;// branch/jalr 在 ID 等待 EX2 中的生产者推进到 WB。
	logic        pc_mem_hazard;// 译码阶段是否存在 PC 与 MEM 阶段的冒险，表示当前指令是否与 MEM 阶段的指令存在数据依赖。
	logic        mem_load_stall;// 译码阶段是否需要因 load 指令而暂停，表示当前指令是否需要等待前一条 load 指令完成。
	logic        mem_stall_flag;// 译码阶段是否需要因 MEM 阶段而暂停，表示当前指令是否需要等待 MEM 阶段的指令完成。
	logic        id_mul_helper_candidate;// 译码阶段是否为 mul helper 候选指令，表示当前指令是否可能是 mul helper 指令。
	logic        id_mul_helper_return_match;// 译码阶段是否匹配 mul helper 返回地址，表示当前指令是否与 mul helper 的返回地址匹配。
	logic        id_mul_helper_hit;// 译码阶段是否命中 mul helper，表示当前指令是否为 mul helper 指令。
	logic [31:0] id_mul_helper_ra;// 译码阶段的 mul helper 返回地址，表示当前指令的 mul helper 返回地址。
	logic [31:0] id_mul_helper_lhs;// 译码阶段的 mul helper 左操作数，表示当前指令的 mul helper 左操作数。
	logic [31:0] id_mul_helper_rhs;// 译码阶段的 mul helper 右操作数，表示当前指令的 mul helper 右操作数。
	logic        id_rf_we;// 译码阶段的寄存器写使能，表示当前指令是否写回寄存器。
	logic [2:0]  id_wb_sel;// 译码阶段的写回选择信号，表示当前指令的写回数据来源。
	logic        id_alu_src_a_sel;// 译码阶段的 ALU 源操作数 A 选择信号，表示当前指令的 ALU 操作数 A 来源。
	logic [1:0]  id_alu_src_b_sel;// 译码阶段的 ALU 源操作数 B 选择信号，表示当前指令的 ALU 操作数 B 来源。
	logic [3:0]  id_alu_op;// 译码阶段的 ALU 操作码，表示当前指令的 ALU 操作类型。
	logic        id_z_light_hit;// 译码阶段是否命中 Z 轻量级指令，表示当前指令是否为 Z 轻量级指令。
	logic [5:0]  id_z_light_op;// 译码阶段的 Z 轻量级指令操作码，表示当前指令的 Z 轻量级操作类型。
	logic [4:0]  id_z_light_shamt;// 译码阶段的 Z 轻量级指令移位量，表示当前指令的 Z 轻量级操作的移位量。
	logic        id_z_light_uses_rs1;// 译码阶段的 Z 轻量级指令是否使用源寄存器1，表示当前指令的 Z 轻量级操作是否使用源寄存器1。
	logic        id_z_light_uses_rs2;// 译码阶段的 Z 轻量级指令是否使用源寄存器2，表示当前指令的 Z 轻量级操作是否使用源寄存器2。
	logic [1:0]  id_pc_sel;// 译码阶段的 PC 选择信号，表示当前指令的下一条指令地址来源。
	logic        id_mem_req;// 译码阶段的存储器请求信号，表示当前指令是否访问存储器。
	logic        id_mem_write;// 译码阶段的存储器写使能，表示当前指令是否写入存储器。
	logic [1:0]  id_mem_mask;// 译码阶段的存储器掩码，表示当前指令的存储器访问字节数。
	logic [2:0]  id_csr_op;// 译码阶段的 CSR 操作码，表示当前指令的 CSR 操作类型。
	logic        id_csr_imm;// 译码阶段的 CSR 立即数标志，表示当前指令是否使用立即数进行 CSR 操作。
	logic [11:0] id_csr_addr;// 译码阶段的 CSR 地址，表示当前指令的 CSR 地址。
	logic [31:0] id_csr_wdata;// 译码阶段的 CSR 写数据，表示当前指令的 CSR 写入数据。
	logic        id_is_ecall;// 译码阶段是否为 ECALL 指令，表示当前指令是否为系统调用。
	logic        id_is_mret;// 译码阶段是否为 MRET 指令，表示当前指令是否为机器模式返回指令。
	logic        id_is_m_ext;// 译码阶段是否为 M 扩展指令，表示当前指令是否为 M 扩展指令。
	logic        id_is_z_light;// 译码阶段是否为 Z 轻量级指令，表示当前指令是否为 Z 轻量级指令。
	logic [3:0]  id_m_op;// 译码阶段的 M 扩展操作码，表示当前指令的 M 扩展操作类型。
	logic [5:0]  id_z_op;// 译码阶段的 Z 轻量级指令操作码，表示当前指令的 Z 轻量级操作类型。
	logic [4:0]  id_z_shamt;// 译码阶段的 Z 轻量级指令移位量，表示当前指令的 Z 轻量级操作的移位量。
	logic        id_fwd_rs1_from_ex2;
	logic        id_fwd_rs1_from_mem;
	logic        id_fwd_rs2_from_ex2;
	logic        id_fwd_rs2_from_mem;

	// =========================
	// ID/EX 流水寄存器 表示译码阶段的指令字段、立即数、寄存器值和控制信号*传递到*执行阶段。
	// =========================
	logic [4:0]  idex1_rs1;           // ID/EX 流水寄存器中的 rs1 地址，表示译码阶段的源寄存器 1 地址传递到执行阶段。
	logic [4:0]  idex1_rs2;           // ID/EX 流水寄存器中的 rs2 地址，表示译码阶段的源寄存器 2 地址传递到执行阶段。
	logic [31:0] idex1_rs1_val;       // ID/EX 流水寄存器中的 rs1 值，表示译码阶段的源寄存器 1 值传递到执行阶段。
	logic [31:0] idex1_rs2_val;       // ID/EX 流水寄存器中的 rs2 值，表示译码阶段的源寄存器 2 值传递到执行阶段。
	logic        idex1_uses_rs1;      // ID/EX 流水寄存器中的 rs1 使用标志，表示译码阶段的指令是否使用源寄存器 1。
	logic        idex1_uses_rs2;      // ID/EX 流水寄存器中的 rs2 使用标志，表示译码阶段的指令是否使用源寄存器 2。
	logic [4:0]  idex1_rd;            // ID/EX 流水寄存器中的 rd 地址，表示译码阶段的目标寄存器地址传递到执行阶段。
	logic [31:0] idex1_imm;           // ID/EX 流水寄存器中的立即数，表示译码阶段的立即数传递到执行阶段。
	logic [31:0] idex1_pc;            // ID/EX 流水寄存器中的 PC 值，表示译码阶段的指令地址传递到执行阶段。
	logic [31:0] idex1_instr;         // ID/EX 流水寄存器中的指令字，供调试观察 EX 同拍控制流。
	logic [2:0]  idex1_funct3;        // ID/EX 流水寄存器中的 funct3 字段，表示译码阶段的 funct3 字段传递到执行阶段。
	logic        idex1_valid;         // ID/EX 流水寄存器中的有效标志，表示译码阶段的指令是否有效。
	logic        idex1_mul_helper;    // ID/EX 流水寄存器中的 mul helper 标志，表示译码阶段的指令是否使用 mul helper。
	logic [31:0] idex1_mul_helper_ra; // ID/EX 流水寄存器中的 mul helper 返回地址，表示译码阶段的 mul helper 返回地址传递到执行阶段。
	logic [31:0] idex1_mul_helper_lhs;// ID/EX 流水寄存器中的 mul helper 左操作数，表示译码阶段的 mul helper 左操作数传递到执行阶段。
	logic [31:0] idex1_mul_helper_rhs;// ID/EX 流水寄存器中的 mul helper 右操作数，表示译码阶段的 mul helper 右操作数传递到执行阶段。
	logic        idex1_rf_we;         // ID/EX 流水寄存器中的寄存器写使能，表示译码阶段的指令是否写回寄存器。
	logic [2:0]  idex1_wb_sel;        // ID/EX 流水寄存器中的写回选择，表示译码阶段的指令写回数据的选择。
	logic        idex1_alu_src_a_sel; // ID/EX 流水寄存器中的 ALU 源操作数 A 选择，表示译码阶段的指令 ALU 操作数 A 的选择。
	logic [1:0]  idex1_alu_src_b_sel; // ID/EX 流水寄存器中的 ALU 源操作数 B 选择，表示译码阶段的指令 ALU 操作数 B 的选择。
	logic [3:0]  idex1_alu_op;        // ID/EX 流水寄存器中的 ALU 操作码，表示译码阶段的指令 ALU 操作类型。
	logic [1:0]  idex1_pc_sel;        // ID/EX 流水寄存器中的 PC 选择，表示译码阶段的指令 PC 的选择。
	logic        idex1_mem_req;       // ID/EX 流水寄存器中的内存请求标志，表示译码阶段的指令是否请求内存操作。
	logic        idex1_mem_write;     // ID/EX 流水寄存器中的内存写标志，表示译码阶段的指令是否进行内存写操作。
	logic [1:0]  idex1_mem_mask;      // ID/EX 流水寄存器中的内存掩码，表示译码阶段的指令内存操作的掩码。
	logic [2:0]  idex1_csr_op;        // ID/EX 流水寄存器中的 CSR 操作码，表示译码阶段的指令 CSR 操作类型。
	logic        idex1_csr_imm;       // ID/EX 流水寄存器中的 CSR 立即数标志，表示译码阶段的指令是否使用立即数进行 CSR 操作。
	logic [11:0] idex1_csr_addr;      // ID/EX 流水寄存器中的 CSR 地址，表示译码阶段的指令 CSR 地址传递到执行阶段。
	logic [31:0] idex1_csr_wdata;     // ID/EX 流水寄存器中的 CSR 写数据，表示译码阶段的指令 CSR 写数据传递到执行阶段。
	logic        idex1_is_ecall;      // ID/EX 流水寄存器中的 ECALL 标志，表示译码阶段的指令是否为 ECALL。
	logic        idex1_is_mret;       // ID/EX 流水寄存器中的 MRET 标志，表示译码阶段的指令是否为 MRET。
	logic        idex1_is_m_ext;      // ID/EX 流水寄存器中的 M 扩展标志，表示译码阶段的指令是否使用 M 扩展。
	logic [3:0]  idex1_m_op;          // ID/EX 流水寄存器中的 M 操作码，表示译码阶段的指令 M 操作类型。
	logic        idex1_is_z_light;    // ID/EX 流水寄存器中的 Z 轻量级指令标志，表示译码阶段的指令是否为 Z 轻量级指令。
	logic [5:0]  idex1_z_op;          // ID/EX 流水寄存器中的 Z 轻量级指令操作码，表示译码阶段的指令 Z 轻量级操作类型。
	logic [4:0]  idex1_z_shamt;       // ID/EX 流水寄存器中的 Z 轻量级指令移位量，表示译码阶段的指令 Z 轻量级操作的移位量。
	logic        idex1_fwd_rs1_from_ex2;
	logic        idex1_fwd_rs1_from_mem;
	logic        idex1_fwd_rs1_from_wb;
	logic        idex1_fwd_rs2_from_ex2;
	logic        idex1_fwd_rs2_from_mem;
	logic        idex1_fwd_rs2_from_wb;

	// =========================
	// EX1 级：forwarding、分支判断、ALU 与跳转目标 表示执行阶段的寄存器值、ALU 输入、分支判断结果和跳转目标。
	// =========================
	// EX1/EX2 pipeline registers
	logic        ex1ex2_valid;
	logic [31:0] ex1ex2_pc;
	logic [31:0] ex1ex2_instr;
	logic [4:0]  ex1ex2_rs1;
	logic [4:0]  ex1ex2_rs2;
`ifdef ENABLE_Z_B_SMALL
	// Z_B_SMALL uses the EX1/EX2 hold path for its one-cycle pending state.
	// In that mode, prefer inferred CE over wide Q->D feedback muxes.
	logic [31:0] ex1ex2_rs1_val;
	logic [31:0] ex1ex2_rs2_val;
	logic [31:0] ex1ex2_alu_a;
	logic [31:0] ex1ex2_alu_b;
	logic [31:0] ex1ex2_store_data;
`else
	// Preserve the proven mainline timing shape when optional Z_B_SMALL is off.
	(* extract_enable = "no" *) logic [31:0] ex1ex2_rs1_val;
	(* extract_enable = "no" *) logic [31:0] ex1ex2_rs2_val;
	(* extract_enable = "no" *) logic [31:0] ex1ex2_alu_a;
	(* extract_enable = "no" *) logic [31:0] ex1ex2_alu_b;
	(* extract_enable = "no" *) logic [31:0] ex1ex2_store_data;
`endif
	logic [4:0]  ex1ex2_rd;
	logic [31:0] ex1ex2_imm;
	logic [2:0]  ex1ex2_funct3;
	logic        ex1ex2_br_take;
	logic        ex1ex2_mul_helper;
	logic [31:0] ex1ex2_mul_helper_ra;
	logic [31:0] ex1ex2_mul_helper_lhs;
	logic [31:0] ex1ex2_mul_helper_rhs;
	logic        ex1ex2_rf_we;
	logic [2:0]  ex1ex2_wb_sel;
	(* max_fanout = 16 *) logic [3:0] ex1ex2_alu_op;
	logic [1:0]  ex1ex2_pc_sel;
	logic        ex1ex2_mem_req;
	logic        ex1ex2_mem_write;
	logic [1:0]  ex1ex2_mem_mask;
	logic [2:0]  ex1ex2_csr_op;
	logic        ex1ex2_csr_imm;
	logic [11:0] ex1ex2_csr_addr;
	logic [31:0] ex1ex2_csr_wdata;
	logic        ex1ex2_is_ecall;
	logic        ex1ex2_is_mret;
	logic        ex1ex2_is_m_ext;
	logic [3:0]  ex1ex2_m_op;
	logic        ex1ex2_is_z_light;
	(* max_fanout = 32 *) logic [5:0] ex1ex2_z_op;
	logic [4:0]  ex1ex2_z_shamt;
	logic [31:0] ex1_rs1_val;      // EX 级寄存器中的 rs1 值，表示执行阶段的指令 rs1 操作数。
	logic [31:0] ex1_rs2_val;      // EX 级寄存器中的 rs2 值，表示执行阶段的指令 rs2 操作数。
	logic [31:0] ex1_pc_rs1_val;   // EX 级寄存器中的 PC+rs1 值，表示执行阶段的指令 PC+rs1 操作数。
	logic [31:0] ex1_pc_rs2_val;   // EX 级寄存器中的 PC+rs2 值，表示执行阶段的指令 PC+rs2 操作数。
	logic [31:0] ex1_alu_a;        // EX 级寄存器中的 ALU 操作数 A，表示执行阶段的指令 ALU 操作数 A。
	logic [31:0] ex1_alu_b;        // EX 级寄存器中的 ALU 操作数 B，表示执行阶段的指令 ALU 操作数 B。
	logic [31:0] ex1_alu_y;        // EX 级寄存器中的 ALU 结果，表示执行阶段的指令 ALU 计算结果。
	logic        ex1_br_take;      // EX 级寄存器中的分支判断结果，表示执行阶段的指令是否采取分支。
	//logic        ex2_pc_fwd_rs1_from_ex1ex2; // EX 级寄存器中的 PC 前递 rs1 来自 EX1/EX2 标志，表示执行阶段的指令是否从 EX1/EX2 前递 rs1。
	//logic        ex2_pc_fwd_rs2_from_ex1ex2; // EX 级寄存器中的 PC 前递 rs2 来自 EX1/EX2 标志，表示执行阶段的指令是否从 EX1/EX2 前递 rs2。
	//logic        ex2_pc_fwd_rs1_from_ex2mem; // EX 级寄存器中的 PC 前递 rs1 来自 EX2/MEM 标志，表示执行阶段的指令是否从 EX2/MEM 前递 rs1。
	//logic        ex2_pc_fwd_rs2_from_ex2mem; // EX 级寄存器中的 PC 前递 rs2 来自 EX2/MEM 标志，表示执行阶段的指令是否从 EX2/MEM 前递 rs2。
	//logic        ex2_pc_fwd_rs1_from_memwb; // EX 级寄存器中的 PC 前递 rs1 来自 MEM/WB 标志，表示执行阶段的指令是否从 MEM/WB 前递 rs1。
	//logic        ex2_pc_fwd_rs2_from_memwb; // EX 级寄存器中的 PC 前递 rs2 来自 MEM/WB 标志，表示执行阶段的指令是否从 MEM/WB 前递 rs2。
	logic        ex1_alu_is_true;  // EX 级寄存器中的 ALU 是否为真标志，表示执行阶段的指令 ALU 结果是否为真。
	logic        ex1_cmp_eq;       // EX 级寄存器中的比较结果标志，表示执行阶段的指令是否相等。
	logic        ex1_cmp_lt_signed; // EX 级寄存器中的有符号比较结果标志，表示执行阶段的指令是否小于。
	logic        ex1_cmp_lt_unsigned; // EX 级寄存器中的无符号比较结果标志，表示执行阶段的指令是否小于。
	logic [31:0] ex1_pc4;          // EX 级寄存器中的 PC+4 值，表示执行阶段的指令 PC+4。
	logic [31:0] ex1_pc_plus_imm;  // EX 级寄存器中的 PC+立即数值，表示执行阶段的指令 PC+立即数。
	logic [31:0] ex1_jalr_sum;     // EX 级寄存器中的 JALR 和，表示执行阶段的指令 JALR 计算结果。
	logic [31:0] ex1_jalr_target;  // EX 级寄存器中的 JALR 目标地址，表示执行阶段的指令 JALR 目标地址。
	logic [63:0] ex1_mul_helper_full; // EX 级寄存器中的乘法辅助全值，表示执行阶段的指令乘法辅助全值。
	logic [31:0] ex1_mul_helper_result; // EX 级寄存器中的乘法辅助结果，表示执行阶段的指令乘法辅助结果。
	logic        ex1_pc_redirect;  // EX 级寄存器中的 PC 重定向标志，表示执行阶段的指令是否需要重定向 PC。
	logic [31:0] ex1_pc_target;    // EX 级寄存器中的 PC 目标地址，表示执行阶段的指令 PC 目标地址。
	logic [31:0] ex1_wb_data;      // EX 级寄存器中的写回数据，表示执行阶段的指令写回数据。
	logic [31:0] ex1_store_data;   // EX 级寄存器中的存储数据，表示执行阶段的指令存储数据。
	logic [31:0] ex1_csr_rdata; // EX 级寄存器中的 CSR 读取数据，表示执行阶段的指令 CSR 读取数据。
	logic [31:0] ex1_csr_wdata; // EX 级寄存器中的 CSR 写入数据，表示执行阶段的指令 CSR 写入数据。
	logic        ex1_csr_we;    // EX 级寄存器中的 CSR 写使能标志，表示执行阶段的指令是否写入 CSR。
	logic        idex1_can_forward_to_ex1ex2; // ID 阶段预判：当前 ID/EX1 下一拍是否可作为 EX1/EX2 前递源。
	logic        ex1ex2_can_forward_to_ex2mem; // ID 阶段预判：当前 EX1/EX2 下一拍是否可作为 EX2/MEM 前递源。
	logic        ex2mem_can_forward_to_memwb; // ID 阶段预判：当前 EX/MEM 下一拍是否可作为 MEM/WB 前递源。
	logic        memwb_can_forward; // MEM/WB 级寄存器中的前递标志，表示 MEM/WB 级寄存器是否可以前递。
	logic        ex1_trap_enter; // EX 级寄存器中的陷入标志，表示执行阶段的指令是否进入陷入。
	logic        ex1_trap_return; // EX 级寄存器中的陷出标志，表示执行阶段的指令是否返回陷入。
	logic        ex1_trap_redirect; // EX 级寄存器中的陷入重定向标志，表示执行阶段的指令是否需要陷入重定向。
	logic [31:0] ex1_trap_target; // EX 级寄存器中的陷入目标地址，表示执行阶段的指令陷入目标地址。
	logic [31:0] ex1_m_result; // EX 级寄存器中的乘法/除法结果，表示执行阶段的指令乘法/除法结果。
	logic [31:0] ex1_mul_result_comb; // EX 级寄存器中的组合乘法结果，表示执行阶段的指令组合乘法结果。
	logic [31:0] ex1_m_result_reg; // EX 级寄存器中的寄存器乘法结果，表示执行阶段的指令寄存器乘法结果。
	logic [63:0] ex1_m_mul_uu_reg; // EX 级寄存器中的乘法结果寄存器，表示执行阶段的指令乘法结果寄存器。
	logic [31:0] ex1_div_result; // EX 级寄存器中的除法结果，表示执行阶段的指令除法结果。
	logic [1:0]  ex1_div_op; // EX 级寄存器中的除法操作，表示执行阶段的指令除法操作。
	logic        ex1_m_is_div; // EX 级寄存器中的除法标志，表示执行阶段的指令是否为除法。
	logic        ex1_m_is_mul; // EX 级寄存器中的乘法标志，表示执行阶段的指令是否为乘法。
	logic [31:0] ex1_z_result; // EX 级寄存器中的 Z 轻量级指令结果，表示执行阶段的指令 Z 轻量级操作结果。
	logic        ex1_z_supported; // EX 级寄存器中的 Z 轻量级指令支持标志，表示执行阶段的指令是否支持 Z 轻量级操作。
	logic        ex1_mul_start; // EX 级寄存器中的乘法开始标志，表示执行阶段的指令是否开始乘法。
	logic        ex1_m_start; // EX 级寄存器中的乘法/除法开始标志，表示执行阶段的指令是否开始乘法/除法。
	logic        ex1_m_inflight; // EX 级寄存器中的乘法/除法进行中标志，表示执行阶段的指令乘法/除法是否进行中。
	logic        ex1_m_result_ready; // EX 级寄存器中的乘法/除法结果准备好标志，表示执行阶段的指令乘法/除法结果是否准备好。
	logic        ex1_m_div_started; // EX 级寄存器中的除法开始标志，表示执行阶段的指令除法是否开始。
	logic        ex1_m_is_div_reg; // EX 级寄存器中的除法寄存器标志，表示执行阶段的指令是否为除法。
	logic        ex1_m_mul_raw_valid; // EX 级寄存器中的乘法原始有效标志，表示执行阶段的指令乘法原始结果是否有效。
	logic [3:0]  ex1_m_op_reg; // EX 级寄存器中的操作码寄存器，表示执行阶段的指令操作码。
	logic [31:0] ex1_m_rs1_reg; // EX 级寄存器中的源操作数1寄存器，表示执行阶段的指令源操作数1。
	logic [31:0] ex1_m_rs2_reg; // EX 级寄存器中的源操作数2寄存器，表示执行阶段的指令源操作数2。
	logic        ex1_div_start; // EX 级寄存器中的除法开始标志，表示执行阶段的指令是否开始除法。
	logic        ex1_div_busy; // EX 级寄存器中的除法忙标志，表示执行阶段的指令除法是否忙。
	logic        ex1_div_done; // EX 级寄存器中的除法完成标志，表示执行阶段的指令除法是否完成。

		// =========================
	// EX2 级：forwarding、分支判断、ALU 与跳转目标 表示执行阶段的寄存器值、ALU 输入、分支判断结果和跳转目标。
	// =========================
	logic [31:0] ex2_rs1_val;      // EX 级寄存器中的 rs1 值，表示执行阶段的指令 rs1 操作数。
	logic [31:0] ex2_rs2_val;      // EX 级寄存器中的 rs2 值，表示执行阶段的指令 rs2 操作数。
	logic [31:0] ex2_pc_rs1_val;   // EX 级寄存器中的 PC+rs1 值，表示执行阶段的指令 PC+rs1 操作数。
	logic [31:0] ex2_pc_rs2_val;   // EX 级寄存器中的 PC+rs2 值，表示执行阶段的指令 PC+rs2 操作数。
	logic [31:0] ex2_alu_a;        // EX 级寄存器中的 ALU 操作数 A，表示执行阶段的指令 ALU 操作数 A。
	logic [31:0] ex2_alu_b;        // EX 级寄存器中的 ALU 操作数 B，表示执行阶段的指令 ALU 操作数 B。
	logic [31:0] ex2_alu_y;        // EX 级寄存器中的 ALU 结果，表示执行阶段的指令 ALU 计算结果。
	logic        ex2_br_take;      // EX 级寄存器中的分支判断结果，表示执行阶段的指令是否采取分支。
	logic        ex2_alu_is_true;  // EX 级寄存器中的 ALU 是否为真标志，表示执行阶段的指令 ALU 结果是否为真。
	logic [31:0] ex2_pc4;          // EX 级寄存器中的 PC+4 值，表示执行阶段的指令 PC+4。
	logic [31:0] ex2_pc_plus_imm;  // EX 级寄存器中的 PC+立即数值，表示执行阶段的指令 PC+立即数。
	logic [31:0] ex2_jalr_sum;     // EX 级寄存器中的 JALR 和，表示执行阶段的指令 JALR 计算结果。
	logic [31:0] ex2_jalr_target;  // EX 级寄存器中的 JALR 目标地址，表示执行阶段的指令 JALR 目标地址。
	logic [63:0] ex2_mul_helper_full; // EX 级寄存器中的乘法辅助全值，表示执行阶段的指令乘法辅助全值。
	logic [31:0] ex2_mul_helper_result; // EX 级寄存器中的乘法辅助结果，表示执行阶段的指令乘法辅助结果。
	logic        ex2_pc_redirect;  // EX 级寄存器中的 PC 重定向标志，表示执行阶段的指令是否需要重定向 PC。
	logic [31:0] ex2_pc_target;    // EX 级寄存器中的 PC 目标地址，表示执行阶段的指令 PC 目标地址。
	logic [31:0] ex2_wb_data;      // EX 级寄存器中的写回数据，表示执行阶段的指令写回数据。
	logic [31:0] ex2_z_wb_data;    // Z 扩展的已验证写回结果。
	logic [31:0] ex2_store_data;   // EX 级寄存器中的存储数据，表示执行阶段的指令存储数据。
	logic [31:0] ex2_csr_rdata; // EX 级寄存器中的 CSR 读取数据，表示执行阶段的指令 CSR 读取数据。
	logic [31:0] ex2_csr_wdata; // EX 级寄存器中的 CSR 写入数据，表示执行阶段的指令 CSR 写入数据。
	logic        ex2_csr_we;    // EX 级寄存器中的 CSR 写使能标志，表示执行阶段的指令是否写入 CSR。
	logic        ex2_trap_enter; // EX 级寄存器中的陷入标志，表示执行阶段的指令是否进入陷入。
	logic        ex2_trap_return; // EX 级寄存器中的陷出标志，表示执行阶段的指令是否返回陷入。
	logic        ex2_trap_redirect; // EX 级寄存器中的陷入重定向标志，表示执行阶段的指令是否需要陷入重定向。
	logic [31:0] ex2_trap_target; // EX 级寄存器中的陷入目标地址，表示执行阶段的指令陷入目标地址。
	logic [31:0] ex2_m_result; // EX 级寄存器中的乘法/除法结果，表示执行阶段的指令乘法/除法结果。
	logic [31:0] ex2_mul_result_comb; // EX 级寄存器中的组合乘法结果，表示执行阶段的指令组合乘法结果。
	logic [31:0] ex2_m_result_reg; // EX 级寄存器中的寄存器乘法结果，表示执行阶段的指令寄存器乘法结果。
	logic [63:0] ex2_m_mul_uu_reg; // EX 级寄存器中的乘法结果寄存器，表示执行阶段的指令乘法结果寄存器。
	logic [31:0] ex2_div_result; // EX 级寄存器中的除法结果，表示执行阶段的指令除法结果。
	logic [1:0]  ex2_div_op; // EX 级寄存器中的除法操作，表示执行阶段的指令除法操作。
	logic        ex2_m_is_div; // EX 级寄存器中的除法标志，表示执行阶段的指令是否为除法。
	logic        ex2_m_is_mul; // EX 级寄存器中的乘法标志，表示执行阶段的指令是否为乘法。
	logic [31:0] ex2_z_result; // EX 级寄存器中的 Z 轻量级指令结果，表示执行阶段的指令 Z 轻量级操作结果。
	logic        ex2_z_supported; // EX 级寄存器中的 Z 轻量级指令支持标志，表示执行阶段的指令是否支持 Z 轻量级操作。
	logic        ex2_mul_start; // EX 级寄存器中的乘法开始标志，表示执行阶段的指令是否开始乘法。
	logic        ex2_m_start; // EX 级寄存器中的乘法/除法开始标志，表示执行阶段的指令是否开始乘法/除法。
	logic        ex2_m_inflight; // EX 级寄存器中的乘法/除法进行中标志，表示执行阶段的指令乘法/除法是否进行中。
	logic        ex2_m_result_ready; // EX 级寄存器中的乘法/除法结果准备好标志，表示执行阶段的指令乘法/除法结果是否准备好。
	logic        ex2_m_div_started; // EX 级寄存器中的除法开始标志，表示执行阶段的指令除法是否开始。
	logic        ex2_m_is_div_reg; // EX 级寄存器中的除法寄存器标志，表示执行阶段的指令是否为除法。
	logic        ex2_m_mul_raw_valid; // EX 级寄存器中的乘法原始有效标志，表示执行阶段的指令乘法原始结果是否有效。
	logic [3:0]  ex2_m_op_reg; // EX 级寄存器中的操作码寄存器，表示执行阶段的指令操作码。
	logic [31:0] ex2_m_rs1_reg; // EX 级寄存器中的源操作数1寄存器，表示执行阶段的指令源操作数1。
	logic [31:0] ex2_m_rs2_reg; // EX 级寄存器中的源操作数2寄存器，表示执行阶段的指令源操作数2。
	logic        ex2_div_start; // EX 级寄存器中的除法开始标志，表示执行阶段的指令是否开始除法。
	logic        ex2_div_busy; // EX 级寄存器中的除法忙标志，表示执行阶段的指令除法是否忙。
	logic        ex2_div_done; // EX 级寄存器中的除法完成标志，表示执行阶段的指令除法是否完成。

	logic        ex2_is_z_b_small;
	logic        z_b_small_start;
	logic        stall_z_b_small;
	logic        hold_ex1ex2;
	logic        z_b_small_pending_q;
	logic [5:0]  z_b_small_op_q;
	logic [4:0]  z_b_small_rd_q;
	logic        z_b_small_rf_we_q;
	logic [2:0]  z_b_small_wb_sel_q;
	logic [31:0] z_b_small_pc_q;
	logic [31:0] z_b_small_partial_q;
	logic [31:0] z_b_small_rs1_q;
	logic [31:0] z_b_small_rs2_q;
	logic [1:0]  z_b_small_shamt_hi_q;
	logic        z_b_small_signed_lt_q;
	logic        z_b_small_unsigned_lt_q;
	logic [4:0]  z_b_small_eff_shamt;
	logic [31:0] z_b_small_rot_s0;
	logic [31:0] z_b_small_rot_s1;
	logic [31:0] z_b_small_rot_s2;
	logic [31:0] z_b_small_stage1_partial;
	logic [31:0] z_b_small_stage2_rot_s3;
	logic [31:0] z_b_small_stage2_rot_s4;
	logic [31:0] z_b_small_final_result;

	// =========================
	// EX2/MEM 流水寄存器 表示执行阶段的结果和控制信号传递到访存阶段。 
	// =========================
	logic [31:0] ex2mem_alu_y      = 32'h0;          // EX/MEM 流水寄存器中的 ALU 结果，表示执行阶段的指令 ALU 计算结果传递到访存阶段。
	logic [31:0] ex2mem_store_data = 32'h0;          // EX/MEM 流水寄存器中的存储数据，表示执行阶段的指令存储数据传递到访存阶段。
	logic [4:0]  ex2mem_rd         = 5'h0;           // EX/MEM 流水寄存器中的目标寄存器，表示执行阶段的指令目标寄存器传递到访存阶段。
	logic [2:0]  ex2mem_funct3     = 3'h0;           // EX/MEM 流水寄存器中的 funct3，表示执行阶段的指令 funct3 传递到访存阶段。
	logic        ex2mem_valid      = 1'b0;           // EX/MEM 流水寄存器中的有效标志，表示执行阶段的指令是否有效传递到访存阶段。
	logic [31:0] ex2mem_wb_data    = 32'h0;          // EX/MEM 流水寄存器中的写回数据，表示执行阶段的指令写回数据传递到访存阶段。
	logic        ex2mem_rf_we      = 1'b0;           // EX/MEM 流水寄存器中的寄存器写使能标志，表示执行阶段的指令是否写回寄存器。
	logic [2:0]  ex2mem_wb_sel     = WB_SRC_ALU;     // EX/MEM 流水寄存器中的写回选择，表示执行阶段的指令写回数据来源。
	logic        ex2mem_mem_req    = 1'b0;                     // EX/MEM 流水寄存器中的存储请求标志，表示执行阶段的指令是否发起存储请求。
	logic        ex2mem_mem_write  = 1'b0;           // EX/MEM 流水寄存器中的存储写标志，表示执行阶段的指令是否进行存储写操作。
	logic [1:0]  ex2mem_mem_mask   = MEM_MASK_WORD;  // EX/MEM 流水寄存器中的存储掩码，表示执行阶段的指令存储操作的字节掩码。
	logic [31:0] ex2mem_pc         = 32'h0;          // EX/MEM 流水寄存器中的程序计数器，表示执行阶段的指令程序计数器传递到访存阶段。
	logic [31:0] ex2mem_addr_base  = 32'h0;          // EX/MEM 流水寄存器中的基地址，表示执行阶段的指令基地址传递到访存阶段。
	logic [31:0] ex2mem_addr_off   = 32'h0;          // EX/MEM 流水寄存器中的偏移地址，表示执行阶段的指令偏移地址传递到访存阶段。
	logic        ex2mem_is_load;                     // EX/MEM 流水寄存器中的加载标志，表示执行阶段的指令是否为加载指令。
	logic        load_in_mem;
	logic [3:0]  ex2mem_store_wstrb = 4'h0;
	logic [31:0] ex2_store_data_aligned;
	logic [3:0]  ex2_store_wstrb;
	logic        ex2_is_dram;
	logic        ex2mem_is_dram = 1'b0;

	// =========================
	// MEM / MEMWB 级 表示访存阶段的结果和控制信号传递到写回阶段。
	// =========================
	logic [31:0] mem_load_data; // MEM 级寄存器中的加载数据，表示访存阶段的指令从内存加载的数据传递到写回阶段。
	logic [31:0] mem_wb_data;   // MEM 级寄存器中的写回数据，表示访存阶段的指令写回数据传递到写回阶段。
	logic [1:0]  mem_load_wait_cnt;// MEM 级寄存器中的加载等待计数，表示访存阶段的指令加载数据需要等待的周期数。
	logic [31:0] memwb_wdata;   // MEM/WB 级寄存器中的写回数据，表示访存阶段的指令写回数据传递到写回阶段。
	logic [4:0]  memwb_rd;      // MEM/WB 级寄存器中的目标寄存器，表示访存阶段的指令目标寄存器传递到写回阶段。
	logic        memwb_rf_we;   // MEM/WB 级寄存器中的寄存器写使能标志，表示访存阶段的指令是否写回寄存器。
	logic        memwb_valid;   // MEM/WB 级寄存器中的有效标志，表示访存阶段的指令是否有效传递到写回阶段。
	logic [31:0] memwb_pc;      // MEM/WB 级寄存器中的程序计数器，表示访存阶段的指令程序计数器传递到写回阶段。
 
	// ========================
	// CSR级控制和状态寄存器 表示控制和状态寄存器的值和写使能信号。
	// ========================
	logic [31:0] csr_mstatus; // CSR 级寄存器中的 mstatus 值，表示机器状态寄存器的值。
	logic [31:0] csr_mtvec;   // CSR 级寄存器中的 mtvec 值，表示机器异常向量基地址寄存器的值。
	logic [31:0] csr_mepc;    // CSR 级寄存器中的 mepc 值，表示机器异常程序计数器的值。
	logic [31:0] csr_mcause;  // CSR 级寄存器中的 mcause 值，表示机器异常原因寄存器的值。
	logic [31:0] csr_mscratch; // CSR 级寄存器中的 mscratch 值，表示机器临时寄存器的值。
 	logic        csr_write_operand_nonzero; // CSR 级寄存器中的写操作数非零标志，表示写入 CSR 的操作数是否非零。
	logic        csr_rs1_is_x0; // CSR 级寄存器中的 rs1 是否为 x0 标志，表示源寄存器 rs1 是否为 x0。

	// ========================
	// MUL寄存器
	// ========================
	logic        m_mul_pp_valid;
	logic [31:0] m_mul_pp_ll, m_mul_pp_lh, m_mul_pp_hl, m_mul_pp_hh;
	(* keep = "true", max_fanout = 1 *) logic [15:0] m_mul_ll_a, m_mul_ll_b;
	(* keep = "true", max_fanout = 1 *) logic [15:0] m_mul_lh_a, m_mul_lh_b;
	(* keep = "true", max_fanout = 1 *) logic [15:0] m_mul_hl_a, m_mul_hl_b;
	(* keep = "true", max_fanout = 1 *) logic [15:0] m_mul_hh_a, m_mul_hh_b;
	// Second operand stage is intentionally not KEEP'ed so Vivado can pack it
	// into the DSP48 AREG/BREG input registers.
	logic [15:0] m_dsp_ll_a, m_dsp_ll_b;
	logic [15:0] m_dsp_lh_a, m_dsp_lh_b;
	logic [15:0] m_dsp_hl_a, m_dsp_hl_b;
	logic [15:0] m_dsp_hh_a, m_dsp_hh_b;
	logic        m_mul_inputs_valid;

	logic [63:0] m_mul_uu_reg;
	logic        mul_start;
	logic        m_start;
	logic        m_inflight;
	logic        m_result_ready;
	logic        m_div_started;
	logic        m_is_div_reg;
	logic        m_mul_raw_valid;
	logic [3:0]  m_op_reg;
	logic [31:0] m_rs1_reg;
	logic [31:0] m_rs2_reg;
	logic        div_start;
	logic        div_busy;
	logic        div_done;
	logic        m_stall; // EX 级寄存器中的乘法/除法暂停标志，表示执行阶段的指令是否需要暂停乘法/除法操作。
	logic        div_stall; // EX 级寄存器中的除法暂停标志，表示执行阶段的指令是否需要暂停除法操作。

	// 根据 load/store 的 funct3 生成字节掩码。
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

	function automatic logic z_b_small_op_is_small(input logic [5:0] z_op);
		begin
			unique case (z_op)
				ZOP_SH1ADD,
				ZOP_SH2ADD,
				ZOP_SH3ADD,
				ZOP_MIN,
				ZOP_MINU,
				ZOP_MAX,
				ZOP_MAXU,
				ZOP_ROL,
				ZOP_ROR,
				ZOP_RORI: z_b_small_op_is_small = 1'b1;
				default:  z_b_small_op_is_small = 1'b0;
			endcase
		end
	endfunction
	
	// 它允许在 helper 入口处直接观察更靠后的写回值，
	// 但为了控制时序，不会无脑复制所有主流水 forwarding 链。
	function automatic logic [31:0] forward_helper_reg(
		input logic [4:0]  reg_addr,
		input logic [31:0] rf_value
	);
		begin
			if (reg_addr == 5'd0) begin
				forward_helper_reg = 32'h0;
			end else begin
				forward_helper_reg = rf_value;
				if (idex1_valid && idex1_rf_we && (idex1_rd == reg_addr) && (idex1_rd != 5'd0) &&
					(idex1_wb_sel != WB_SRC_MEM)) begin
					forward_helper_reg = ex2_wb_data;
				end else if (ex2mem_valid && ex2mem_rf_we && (ex2mem_rd == reg_addr) && (ex2mem_rd != 5'd0) &&
					(ex2mem_wb_sel != WB_SRC_MEM)) begin
					forward_helper_reg = ex2mem_wb_data;
				end else if (memwb_valid && memwb_rf_we && (memwb_rd == reg_addr) && (memwb_rd != 5'd0)) begin
					forward_helper_reg = memwb_wdata;
				end
			end
		end
	endfunction

	// helper operand 的前递更保守：只看 EXMEM / MEMWB，
	// 避免把当前 EX 结果再次折回 helper 判定路径里。
	function automatic logic [31:0] forward_helper_operand_reg(
		input logic [4:0]  reg_addr,
		input logic [31:0] rf_value
	);
		begin
			if (reg_addr == 5'd0) begin
				forward_helper_operand_reg = 32'h0;
			end else begin
				forward_helper_operand_reg = rf_value;
				if (ex2mem_valid && ex2mem_rf_we && (ex2mem_rd == reg_addr) && (ex2mem_rd != 5'd0) &&
					(ex2mem_wb_sel != WB_SRC_MEM)) begin
					forward_helper_operand_reg = ex2mem_wb_data;
				end else if (memwb_valid && memwb_rf_we && (memwb_rd == reg_addr) && (memwb_rd != 5'd0)) begin
					forward_helper_operand_reg = memwb_wdata;
				end
			end
		end
	endfunction

	// 对外总线连接：真正发起访存的是 EX/MEM 级。
	assign irom_addr   = pc_q[13:2];
	// PC 在 fetch_stall 时保持不变，因此 BRAM 可以始终使能并重复读取同一地址。
	// 避免“译码/冒险判断 -> fetch_stall -> BRAM ENARDEN”的长组合路径。
	assign irom_en     = 1'b1;
	assign perip_addr  = ex2mem_alu_y;
	assign perip_wen   = ex2mem_valid && ex2mem_mem_req && ex2mem_mem_write;
	assign perip_mask  = ex2mem_mem_mask;
	assign perip_wstrb = (perip_wen && ex2mem_is_dram) ? ex2mem_store_wstrb : 4'b0000;
	assign perip_wdata = ex2mem_store_data;

	// 指令字段译码。
	mycpu_rv32_decode u_dec (
		.instr  (ifid_instr),
		.opcode (id_opcode),
		.funct3 (id_funct3),
		.funct7 (id_funct7),
		.rd     (id_rd),
		.rs1    (id_rs1),
		.rs2    (id_rs2)
	);

	// 除法器
	rv32_divider u_div (
		.clk   (cpu_clk),
		.rst   (cpu_rst),
		.start (div_start),
		.op    (ex2_div_op),
		.rs1   (m_rs1_reg),
		.rs2   (m_rs2_reg),
		.busy  (div_busy),
		.done  (div_done),
		.result(ex2_div_result)
	);

	// 立即数扩展。
	IMMGEN #(32) u_imm (
		.instr (ifid_instr),
		.imm   (id_imm_raw)
	);

	// 通用寄存器堆。
	RF #(5, 32) u_rf (
		.clk     (cpu_clk),
		.rst     (cpu_rst),
		//写回发生在 MEM/WB。
		.wen     (memwb_rf_we && memwb_valid),
		.waddr   (memwb_rd),
		.wdata   (memwb_wdata),
		//
		.rR1     (id_rs1),
		.rR2     (id_rs2),
		.rR1_data(rf_rs1_raw),
		.rR2_data(rf_rs2_raw),
		.x1_data (rf_x1_raw),
		.x10_data(rf_x10_raw),
		.x11_data(rf_x11_raw)
	);

	// EX 级主 ALU。
	ALU #(32) u_alu (
		.A          (ex1ex2_alu_a),
		.B          (ex1ex2_alu_b),
		.ALUOp      (ex1ex2_alu_op),
		.Result     (ex2_alu_y),
		.isTrue     (ex2_alu_is_true)
	);

	z_light_decode u_z_light_decode (
		.instr      (ifid_instr),

		.z_hit     (id_z_light_hit),
		.z_op      (id_z_light_op),
		.z_shamt   (id_z_light_shamt),
		.z_uses_rs1(id_z_light_uses_rs1),
		.z_uses_rs2(id_z_light_uses_rs2)
	);

	z_light_unit #(
		.ENABLE_Z_B_SMALL(1'b0)
	) u_z_light_unit (
		.z_valid    (ex1ex2_valid),
		.z_op       (ex1ex2_z_op),
		.rs1_val    (ex1ex2_rs1_val),
		.rs2_val    (ex1ex2_rs2_val),
		.z_shamt	(ex1ex2_z_shamt),
		.z_result   (ex2_z_result),
		.z_supported(ex2_z_supported)
	);

	// store 数据只在 store 指令时有效，其余时间清零有利于减少无关逻辑传播。
	assign ex2_store_data    = ex1ex2_mem_write ? ex1ex2_store_data : 32'h0;
	assign ex2_is_dram       = (ex2_alu_y[31:18] == DRAM_REGION_TAG);
	always_comb begin
		ex2_store_data_aligned = ex2_store_data;
		ex2_store_wstrb = 4'b0000;
		if (ex1ex2_valid && ex1ex2_mem_req && ex1ex2_mem_write) begin
			unique case (ex1ex2_mem_mask)
				MEM_MASK_BYTE: begin
					ex2_store_data_aligned = {4{ex2_store_data[7:0]}};
					ex2_store_wstrb = 4'b0001 << ex2_alu_y[1:0];
				end
				MEM_MASK_HALF: begin
					ex2_store_data_aligned = {2{ex2_store_data[15:0]}};
					ex2_store_wstrb = ex2_alu_y[1] ? 4'b1100 : 4'b0011;
				end
				MEM_MASK_WORD: begin
					ex2_store_wstrb = 4'b1111;
				end
				default: begin
					ex2_store_wstrb = 4'b0000;
				end
			endcase
		end
	end
	assign ex2_pc4           = ex1ex2_pc + 32'd4;
	assign ex2_pc_plus_imm   = ex1ex2_pc + ex1ex2_imm;

	assign ex2_is_z_b_small = CPU_ENABLE_Z_B_SMALL &&
							  ex1ex2_valid &&
							  ex1ex2_is_z_light &&
							  z_b_small_op_is_small(ex1ex2_z_op);
	assign z_b_small_start  = ex2_is_z_b_small &&
							  !z_b_small_pending_q &&
							  !mem_load_stall &&
							  !m_stall;
	assign stall_z_b_small  = z_b_small_start;
	assign hold_ex1ex2      = mem_load_stall || m_stall || stall_z_b_small;

	always_comb begin
		z_b_small_eff_shamt = ex1ex2_rs2_val[4:0];
		if (ex1ex2_z_op == ZOP_RORI) begin
			z_b_small_eff_shamt = ex1ex2_z_shamt;
		end else if (ex1ex2_z_op == ZOP_ROL) begin
			z_b_small_eff_shamt = (~ex1ex2_rs2_val[4:0] + 5'd1) & 5'h1f;
		end
	end

	assign z_b_small_rot_s0 = z_b_small_eff_shamt[0] ? {ex1ex2_rs1_val[0],    ex1ex2_rs1_val[31:1]} : ex1ex2_rs1_val;
	assign z_b_small_rot_s1 = z_b_small_eff_shamt[1] ? {z_b_small_rot_s0[1:0], z_b_small_rot_s0[31:2]} : z_b_small_rot_s0;
	assign z_b_small_rot_s2 = z_b_small_eff_shamt[2] ? {z_b_small_rot_s1[3:0], z_b_small_rot_s1[31:4]} : z_b_small_rot_s1;

	always_comb begin
		unique case (ex1ex2_z_op)
			ZOP_SH1ADD: z_b_small_stage1_partial = {ex1ex2_rs1_val[30:0], 1'b0};
			ZOP_SH2ADD: z_b_small_stage1_partial = {ex1ex2_rs1_val[29:0], 2'b00};
			ZOP_SH3ADD: z_b_small_stage1_partial = {ex1ex2_rs1_val[28:0], 3'b000};
			ZOP_ROL,
			ZOP_ROR,
			ZOP_RORI:  z_b_small_stage1_partial = z_b_small_rot_s2;
			default:   z_b_small_stage1_partial = ex1ex2_rs1_val;
		endcase
	end

	assign z_b_small_stage2_rot_s3 = z_b_small_shamt_hi_q[0] ? {z_b_small_partial_q[7:0],  z_b_small_partial_q[31:8]}  : z_b_small_partial_q;
	assign z_b_small_stage2_rot_s4 = z_b_small_shamt_hi_q[1] ? {z_b_small_stage2_rot_s3[15:0], z_b_small_stage2_rot_s3[31:16]} : z_b_small_stage2_rot_s3;

	always_comb begin
		unique case (z_b_small_op_q)
			ZOP_SH1ADD,
			ZOP_SH2ADD,
			ZOP_SH3ADD: z_b_small_final_result = z_b_small_partial_q + z_b_small_rs2_q;
			ZOP_MIN:    z_b_small_final_result = z_b_small_signed_lt_q   ? z_b_small_rs1_q : z_b_small_rs2_q;
			ZOP_MINU:   z_b_small_final_result = z_b_small_unsigned_lt_q ? z_b_small_rs1_q : z_b_small_rs2_q;
			ZOP_MAX:    z_b_small_final_result = z_b_small_signed_lt_q   ? z_b_small_rs2_q : z_b_small_rs1_q;
			ZOP_MAXU:   z_b_small_final_result = z_b_small_unsigned_lt_q ? z_b_small_rs2_q : z_b_small_rs1_q;
			ZOP_ROL,
			ZOP_ROR,
			ZOP_RORI:   z_b_small_final_result = z_b_small_stage2_rot_s4;
			default:    z_b_small_final_result = z_b_small_partial_q;
		endcase
	end

	// JALR 的目标地址单独计算，避免普通 ALU 输出再回绕到 PC 选择链上。
	always_comb begin
		if (ex1ex2_valid && (ex1ex2_pc_sel == PC_SRC_JALR)) begin
			ex2_jalr_sum = ex2_rs1_val + ex1ex2_imm;
		end else begin
			ex2_jalr_sum = 32'h0;
		end
	end

	assign ex2_jalr_target   = {ex2_jalr_sum[31:1], 1'b0};
	// helper 乘法用组合乘法器，仅在 helper 命中时结果才会真正写回。
	assign ex2_mul_helper_full     = $unsigned(ex1ex2_mul_helper_lhs) * $unsigned(ex1ex2_mul_helper_rhs);
	assign ex2_mul_helper_result   = ex2_mul_helper_full[31:0];
	// helper 命中条件：当前 IF/ID 正好来到指定 PC，并且返回地址匹配预期模板。
	assign id_mul_helper_candidate = ENABLE_MUL_HELPER_ACCEL && ifid_valid && !idex1_mul_helper && (ifid_pc == MUL_HELPER_PC);
	assign id_mul_helper_ra       = id_mul_helper_candidate ? forward_helper_reg(5'd1, rf_x1_raw) : 32'h0;
	assign id_mul_helper_return_match = (id_mul_helper_ra == MUL_HELPER_LOOP004_RA) ||
									 (id_mul_helper_ra == MUL_HELPER_LOOP006_RA);
	assign id_mul_helper_hit      = id_mul_helper_candidate && id_mul_helper_return_match;
	assign id_mul_helper_lhs      = id_mul_helper_hit ? forward_helper_operand_reg(5'd10, rf_x10_raw) : 32'h0;
	assign id_mul_helper_rhs      = id_mul_helper_hit ? forward_helper_operand_reg(5'd11, rf_x11_raw) : 32'h0;
	// B/J 型立即数这里直接按指令格式重新拼接，剩余情况沿用通用 IMMGEN 输出。
	assign id_imm           = (id_opcode == OPC_BRANCH) ? {{19{ifid_instr[31]}}, ifid_instr[31], ifid_instr[7], ifid_instr[30:25], ifid_instr[11:8], 1'b0} :
							  (id_opcode == OPC_JAL)    ? {{11{ifid_instr[31]}}, ifid_instr[31], ifid_instr[19:12], ifid_instr[20], ifid_instr[30:21], 1'b0} :
							  id_imm_raw;
	// CSR 指令类型译码。
	assign id_is_ecall = ifid_valid && (ifid_instr == 32'h0000_0073);
	assign id_is_mret  = ifid_valid && (ifid_instr == 32'h3020_0073);
	assign id_is_m_ext = ifid_valid &&
						 (id_opcode == OPC_OP) &&
						 (id_funct7 == 7'b0000001);

	// ID 阶段提前记录消费者下一拍进入 EX1 时应使用的来源：EX2、MEM 或 WB。
	// 三条 EX1 前递的优先级在 EX1 组合逻辑中固定为 EX2 > MEM > WB。
	// 只让普通 ALU 结果走 EX2 -> EX1 快速旁路；PC+4、IMM_U、CSR、M 扩展、
	// helper 和 Z_B_SMALL 等路径仍等待到 EX2/MEM，避免把长结果链拉回 EX1。
	assign idex1_can_forward_to_ex1ex2 = idex1_valid && idex1_rf_we &&
									     (idex1_rd != 5'h0) &&
									     (idex1_wb_sel == WB_SRC_ALU) &&
									     !idex1_is_m_ext &&
									     !idex1_mul_helper;
	assign ex1ex2_can_forward_to_ex2mem = ex1ex2_valid && ex1ex2_rf_we &&
										 (ex1ex2_rd != 5'h0) &&
										 (ex1ex2_wb_sel != WB_SRC_MEM) &&
										 (!ex1ex2_is_m_ext || m_result_ready);
	assign ex2mem_can_forward_to_memwb = ex2mem_valid && ex2mem_rf_we && (ex2mem_rd != 5'h0);
	assign memwb_can_forward = memwb_valid && memwb_rf_we && (memwb_rd != 5'h0);
	assign id_fwd_rs1_from_ex2 = ifid_valid && id_uses_rs1 &&
								   idex1_can_forward_to_ex1ex2 &&
								   (id_rs1 == idex1_rd);
	assign id_fwd_rs1_from_mem = ifid_valid && id_uses_rs1 &&
								   ex1ex2_can_forward_to_ex2mem &&
								   (id_rs1 == ex1ex2_rd);
	assign id_fwd_rs1_from_wb = ifid_valid && id_uses_rs1 &&
								 ex2mem_can_forward_to_memwb &&
								 (id_rs1 == ex2mem_rd);
	assign id_fwd_rs2_from_ex2 = ifid_valid && id_uses_rs2 &&
								   idex1_can_forward_to_ex1ex2 &&
								   (id_rs2 == idex1_rd);
	assign id_fwd_rs2_from_mem = ifid_valid && id_uses_rs2 &&
								   ex1ex2_can_forward_to_ex2mem &&
								   (id_rs2 == ex1ex2_rd);
	assign id_fwd_rs2_from_wb = ifid_valid && id_uses_rs2 &&
								 ex2mem_can_forward_to_memwb &&
								 (id_rs2 == ex2mem_rd);
	assign ex2mem_is_load = ex2mem_valid && ex2mem_mem_req && !ex2mem_mem_write;
	//现在关闭forwarding，避免 timing 过长，load-branch冒险的解决方案为再等一拍。
	//assign ex2_pc_fwd_rs1_from_exmem = 1'b0;
	//assign ex2_pc_fwd_rs1_from_memwb = 1'b0;
	//assign ex2_pc_fwd_rs2_from_exmem = 1'b0;
	//assign ex2_pc_fwd_rs2_from_memwb = 1'b0;
	assign ex2_trap_enter = ex1ex2_valid && ex1ex2_is_ecall && !mem_load_stall;
	assign ex2_trap_return = ex1ex2_valid && ex1ex2_is_mret && !mem_load_stall;
	assign ex2_trap_redirect = ex2_trap_enter || ex2_trap_return;
	assign ex2_trap_target =
		ex2_trap_enter  ? {csr_mtvec[31:2], 2'b00} :
		ex2_trap_return ? csr_mepc :
						 32'h0;
	assign csr_rs1_is_x0 = (ex1ex2_rs1 == 5'd0);
	assign csr_write_operand_nonzero = (ex1ex2_csr_imm ? (ex1ex2_csr_wdata != 32'h0)
                                                 : !csr_rs1_is_x0);// CSR 写入操作数非零条件。
	// 乘法统一先做无符号 32x32，高位带符号的修正在下一拍完成，
	// 用寄存器把 DSP 乘法链和后面的高位修正链拆开。
	assign ex2_m_is_div = ex1ex2_valid && ex1ex2_is_m_ext &&
						 ((ex1ex2_m_op == M_OP_DIV) ||
						  (ex1ex2_m_op == M_OP_DIVU) ||
						  (ex1ex2_m_op == M_OP_REM) ||
						  (ex1ex2_m_op == M_OP_REMU));
	assign ex2_m_is_mul = ex1ex2_valid && ex1ex2_is_m_ext && !ex2_m_is_div && (ex1ex2_m_op != M_OP_NONE);
	assign m_start   = ex1ex2_valid && ex1ex2_is_m_ext && !m_inflight && !m_result_ready && !ex2_pc_redirect;
	assign mul_start = m_start && ex2_m_is_mul;
	assign div_start = m_inflight && m_is_div_reg && !m_div_started;
	assign div_stall = ex2_m_is_div && !div_done;
	assign m_stall = ex1ex2_valid && ex1ex2_is_m_ext && !m_result_ready;

	// div_op 译码，传给除法器。
	always_comb begin
		case (ex1ex2_m_op)
			M_OP_DIV:  ex2_div_op = 2'd0;
			M_OP_DIVU: ex2_div_op = 2'd1;
			M_OP_REM:  ex2_div_op = 2'd2;
			M_OP_REMU: ex2_div_op = 2'd3;
			default:   ex2_div_op = 2'd0;
		endcase
	end

	// ID 级允许从 MEMWB 做“同拍旁路读取”，减少读后写停顿。
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

	// EX 级乘法结果选择：低位/高位/有符号修正。
	always_comb begin
		case (m_op_reg)
			M_OP_MUL:    ex2_mul_result_comb = m_mul_uu_reg[31:0];
			M_OP_MULH:   ex2_mul_result_comb = m_mul_uu_reg[63:32]
										 - (m_rs1_reg[31] ? m_rs2_reg : 32'h0)
										 - (m_rs2_reg[31] ? m_rs1_reg : 32'h0);
			M_OP_MULHSU: ex2_mul_result_comb = m_mul_uu_reg[63:32]
										 - (m_rs1_reg[31] ? m_rs2_reg : 32'h0);
			M_OP_MULHU:  ex2_mul_result_comb = m_mul_uu_reg[63:32];
			default:     ex2_mul_result_comb = 32'h0;
		endcase
	end
	
	// M 级状态机：乘法/除法的结果在 EX 级就可以直接写回。
	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			m_inflight   <= 1'b0;
			m_result_ready <= 1'b0;
			m_div_started <= 1'b0;
			m_is_div_reg <= 1'b0;
			m_mul_pp_valid <= 1'b0;
			m_mul_inputs_valid <= 1'b0;
			m_mul_raw_valid <= 1'b0;
			m_op_reg     <= M_OP_NONE;
			m_rs1_reg    <= 32'h0;
			m_rs2_reg    <= 32'h0;
			m_mul_ll_a   <= 16'h0;
			m_mul_ll_b   <= 16'h0;
			m_mul_lh_a   <= 16'h0;
			m_mul_lh_b   <= 16'h0;
			m_mul_hl_a   <= 16'h0;
			m_mul_hl_b   <= 16'h0;
			m_mul_hh_a   <= 16'h0;
			m_mul_hh_b   <= 16'h0;
			m_mul_pp_ll  <= 32'h0;
			m_mul_pp_lh  <= 32'h0;
			m_mul_pp_hl  <= 32'h0;
			m_mul_pp_hh  <= 32'h0;
			m_mul_uu_reg <= 64'h0;
			ex2_m_result_reg <= 32'h0;
		end else if (m_start) begin
			m_inflight     <= 1'b1;
			m_result_ready <= 1'b0;
			m_div_started  <= 1'b0;
			m_is_div_reg   <= ex2_m_is_div;
			m_mul_pp_valid <= 1'b0;
			m_mul_inputs_valid <= 1'b0;
			m_mul_raw_valid <= 1'b0;
			m_op_reg       <= ex1ex2_m_op;
			m_rs1_reg      <= ex1ex2_rs1_val;
			m_rs2_reg      <= ex1ex2_rs2_val;
			// Give each partial-product DSP its own local operand registers.
			m_mul_ll_a     <= ex1ex2_rs1_val[15:0];
			m_mul_ll_b     <= ex1ex2_rs2_val[15:0];
			m_mul_lh_a     <= ex1ex2_rs1_val[15:0];
			m_mul_lh_b     <= ex1ex2_rs2_val[31:16];
			m_mul_hl_a     <= ex1ex2_rs1_val[31:16];
			m_mul_hl_b     <= ex1ex2_rs2_val[15:0];
			m_mul_hh_a     <= ex1ex2_rs1_val[31:16];
			m_mul_hh_b     <= ex1ex2_rs2_val[31:16];
		end else if (m_inflight && m_is_div_reg) begin
			if (!m_div_started) begin
				m_div_started <= 1'b1;
			end
			if (div_done) begin
				ex2_m_result_reg <= ex2_div_result;
				m_result_ready <= 1'b1;
				m_inflight <= 1'b0;
				m_div_started <= 1'b0;
			end
		end else if (m_inflight && !m_mul_inputs_valid) begin
			// This extra cycle lets the following registers map to DSP48 AREG/BREG.
			m_mul_inputs_valid <= 1'b1;
		end else if (m_inflight && !m_mul_pp_valid) begin
			// Four independent 16x16 products avoid a cascaded 32x32 DSP path.
			m_mul_pp_ll <= $unsigned(m_dsp_ll_a) * $unsigned(m_dsp_ll_b);
			m_mul_pp_lh <= $unsigned(m_dsp_lh_a) * $unsigned(m_dsp_lh_b);
			m_mul_pp_hl <= $unsigned(m_dsp_hl_a) * $unsigned(m_dsp_hl_b);
			m_mul_pp_hh <= $unsigned(m_dsp_hh_a) * $unsigned(m_dsp_hh_b);
			m_mul_pp_valid <= 1'b1;
		end else if (m_inflight && !m_mul_raw_valid) begin
			m_mul_uu_reg <= {32'h0, m_mul_pp_ll}
						  + {16'h0, m_mul_pp_lh, 16'h0}
						  + {16'h0, m_mul_pp_hl, 16'h0}
						  + {m_mul_pp_hh, 32'h0};
			m_mul_raw_valid <= 1'b1;
		end else if (m_inflight) begin
			ex2_m_result_reg <= ex2_mul_result_comb;
			m_result_ready <= 1'b1;
			m_inflight <= 1'b0;
			m_mul_pp_valid <= 1'b0;
			m_mul_inputs_valid <= 1'b0;
			m_mul_raw_valid <= 1'b0;
		end else if (m_result_ready && !m_stall) begin
			m_result_ready <= 1'b0;
			m_op_reg <= M_OP_NONE;
		end
	end

	// No asynchronous reset here: DSP48 AREG/BREG only need these operands
	// after m_mul_inputs_valid is asserted, and can therefore absorb this stage.
	always_ff @(posedge cpu_clk) begin
		if (m_inflight && !m_is_div_reg && !m_mul_inputs_valid) begin
			m_dsp_ll_a <= m_mul_ll_a;
			m_dsp_ll_b <= m_mul_ll_b;
			m_dsp_lh_a <= m_mul_lh_a;
			m_dsp_lh_b <= m_mul_lh_b;
			m_dsp_hl_a <= m_mul_hl_a;
			m_dsp_hl_b <= m_mul_hl_b;
			m_dsp_hh_a <= m_mul_hh_a;
			m_dsp_hh_b <= m_mul_hh_b;
		end
	end

	// M 扩展结果选择：乘法/除法的结果在 EX 级就可以直接写回。
	always_comb begin
		case (ex1ex2_m_op)
			M_OP_MUL,
			M_OP_MULH,
			M_OP_MULHSU,
			M_OP_MULHU:  ex2_m_result = ex2_m_result_reg;
			M_OP_DIV,
			M_OP_DIVU,
			M_OP_REM,
			M_OP_REMU:  ex2_m_result = ex2_m_result_reg;
			default:     ex2_m_result = 32'h0;
		endcase
	end

	// PC redirect 判定：trap / helper / branch / jump 统一在 EX 级生效。
	always_comb begin
		ex2_pc_redirect = 1'b0;

		if (ex1ex2_valid && !mem_load_stall) begin
			if (ex2_trap_enter || ex2_trap_return) begin
				ex2_pc_redirect = 1'b1;
			end else if (ex1ex2_mul_helper) begin
				ex2_pc_redirect = 1'b1;
			end else begin
				case (ex1ex2_pc_sel)
					PC_SRC_BRANCH: begin
						if (ex2_br_take) begin
							ex2_pc_redirect = 1'b1;
						end
					end

					PC_SRC_JAL: begin
						ex2_pc_redirect = 1'b1;
					end

					PC_SRC_JALR: begin
						ex2_pc_redirect = 1'b1;
					end

					default: begin end
				endcase
			end
		end
	end

	// IF1/IF2 共用的暂停条件。同步 BRAM 停止读地址时，配套的 PC/valid 也必须保持。
	assign fetch_stall = load_use_ex1_hazard || load_use_ex2_hazard ||
						 slow_result_ex1_hazard ||
						 pc_ex1_hazard || pc_ex2_hazard || pc_mem_hazard ||
						 m_issue_hazard || mem_load_stall || m_stall || stall_z_b_small;

	// IF 级 PC 更新优先级：redirect > stall/hold > 顺序 +4。
	always_comb begin
		if (ex2_pc_redirect) begin
			//如果 EX 阶段要求跳转，PC = 跳转目标
			//包括：branch_taken jal jalr ecall mret mul_helper
			pc_next = ex2_pc_target;
		end else if (fetch_stall) begin
			//如果存在相关冒险或停顿，PC 保持不变
			pc_next = pc_q;
		end else begin
			//顺序执行，PC + 4
			pc_next = pc_q + 32'd4;
		end
	end

	// IF 级 PC 寄存器，在 reset 时初始化为 RESET_PC。
	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			pc_q <= RESET_PC;
		end else begin
			pc_q <= pc_next;
		end
	end

	// IF1：记录本拍送入同步 BRAM 的 PC。BRAM 下一拍返回数据时用它完成 PC/指令配对。
	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			fetch_pc_q    <= RESET_PC;
			fetch_valid <= 1'b0;
		end else if (ex2_pc_redirect) begin
			// redirect 发生时，BRAM 管线中的顺序路径请求已经无效。
			fetch_valid <= 1'b0;
		end else if (fetch_stall) begin
			// 保留尚未送入 IF/ID 的请求信息；对应指令由 fetch_hold_* 暂存。
		end else begin
			fetch_pc_q    <= pc_q;
			fetch_valid <= 1'b1;
		end
	end

	// IROM 常开时，stall 的第一个时钟沿会让 BRAM 继续读取下一地址。
	// 用一个 skid entry 保存原本尚未进入 IF/ID 的 PC/指令对，解除 stall 时优先消费它。
	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst || ex2_pc_redirect) begin
			fetch_hold_pc    <= RESET_PC;
			fetch_hold_instr <= NOP_INSTR;
			fetch_hold_valid <= 1'b0;
			fetch_hold_full  <= 1'b0;
		end else begin
			// 数据寄存器只由本地 full 标志控制，不再由长路径 fetch_stall 驱动 CE。
			// stall 第一拍到来时旧 full 仍为 0，因此会恰好保存尚未进入 IF/ID 的请求。
			if (!fetch_hold_full) begin
				fetch_hold_pc    <= fetch_pc_q;
				fetch_hold_instr <= irom_data;
				fetch_hold_valid <= fetch_valid;
			end

			// 复杂的冒险判断现在只驱动这一个标志寄存器。
			fetch_hold_full <= fetch_stall;
		end
	end

	// IF2 valid/control: redirect only invalidates the entry.  The wide
	// PC/instruction payload does not need to be cleared when valid is zero.
	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			ifid_valid <= 1'b0;
		end else if (ex2_pc_redirect) begin
			ifid_valid <= 1'b0;
		end else if (fetch_stall) begin
			// Hold the current valid state while the consumer waits.
		end else if (fetch_hold_full) begin
			ifid_valid <= fetch_hold_valid;
		end else begin
			ifid_valid <= fetch_valid;
		end
	end

	// IF2 payload: its value is don't-care whenever ifid_valid is zero, so the
	// branch redirect signal is kept out of these 64 wide-register data paths.
	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			ifid_pc    <= RESET_PC;
			ifid_instr <= NOP_INSTR;
		end else if (fetch_stall) begin
			// Hold the current payload while the consumer waits.
		end else if (fetch_hold_full) begin
			ifid_pc    <= fetch_hold_pc;
			ifid_instr <= fetch_hold_instr;
		end else begin
			ifid_pc    <= fetch_pc_q;
			ifid_instr <= irom_data;
		end
	end

	// ID 级主控制器：这里只做组合译码，不直接写流水寄存器。
	// 负责告诉后面的流水线：
	//
	//这条指令用不用 rs1
	//用不用 rs2
	//写不写 rd
	//写回来源是什么
	//ALU 做什么
	//是不是访存
	//是不是 CSR
	//是不是 M 扩展
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
		id_csr_op    = CSR_OP_NONE;
		id_csr_imm   = 1'b0;
		id_csr_addr  = ifid_instr[31:20];
		id_csr_wdata = 32'h0;
		id_m_op      = M_OP_NONE;
		id_is_z_light = 1'b0;
		id_z_op       = ZOP_NONE;
		id_z_shamt    = ifid_instr[24:20];

		if (ifid_valid) begin
			if (id_z_light_hit) begin
				id_uses_rs1      = id_z_light_uses_rs1;
				id_uses_rs2      = id_z_light_uses_rs2;
				id_rf_we         = (id_rd != 5'd0);
				id_wb_sel        = WB_SRC_Z;

				// 这几个保持普通默认值即可
				id_alu_src_a_sel = ALU_SRC_A_RS1;
				id_alu_src_b_sel = ALU_SRC_B_RS2;
				id_alu_op        = ALU_ADD;
				id_pc_sel        = PC_SRC_PC4;
				id_mem_req       = 1'b0;
				id_mem_write     = 1'b0;
				id_mem_mask      = MEM_MASK_WORD;
				id_csr_op        = CSR_OP_NONE;
				id_m_op          = M_OP_NONE;

				id_is_z_light    = 1'b1;
				id_z_op          = id_z_light_op;
				id_z_shamt       = id_z_light_shamt;
			end else begin
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
					if(id_funct7 == 7'b0000001) begin
						id_m_op = M_OP_NONE;
						if (id_is_m_ext) begin
							unique case (id_funct3)
								3'b000: id_m_op = M_OP_MUL;
								3'b001: id_m_op = M_OP_MULH;
								3'b010: id_m_op = M_OP_MULHSU;
								3'b011: id_m_op = M_OP_MULHU;
								3'b100: id_m_op = M_OP_DIV;
								3'b101: id_m_op = M_OP_DIVU;
								3'b110: id_m_op = M_OP_REM;
								3'b111: id_m_op = M_OP_REMU;
								default: id_m_op = M_OP_NONE;
							endcase
						end
					end else begin
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

				OPC_SYSTEM: begin
					id_rf_we  = 1'b0;
					id_wb_sel = WB_SRC_CSR;

					case (id_funct3)
						3'b001: begin // CSRRW
							id_uses_rs1  = 1'b1;
							id_rf_we     = (id_rd != 5'd0);
							id_csr_op    = CSR_OP_CSRRW;
							id_csr_imm   = 1'b0;
							id_csr_wdata = id_rs1_val;
						end

						3'b010: begin // CSRRS
							id_uses_rs1  = 1'b1;
							id_rf_we     = (id_rd != 5'd0);
							id_csr_op    = CSR_OP_CSRRS;
							id_csr_imm   = 1'b0;
							id_csr_wdata = id_rs1_val;
						end

						3'b011: begin // CSRRC
							id_uses_rs1  = 1'b1;
							id_rf_we     = (id_rd != 5'd0);
							id_csr_op    = CSR_OP_CSRRC;
							id_csr_imm   = 1'b0;
							id_csr_wdata = id_rs1_val;
						end

						3'b101: begin // CSRRWI
							id_rf_we     = (id_rd != 5'd0);
							id_csr_op    = CSR_OP_CSRRW;
							id_csr_imm   = 1'b1;
							id_csr_wdata = {27'h0, id_rs1};
						end

						3'b110: begin // CSRRSI
							id_rf_we     = (id_rd != 5'd0);
							id_csr_op    = CSR_OP_CSRRS;
							id_csr_imm   = 1'b1;
							id_csr_wdata = {27'h0, id_rs1};
						end

						3'b111: begin // CSRRCI
							id_rf_we     = (id_rd != 5'd0);
							id_csr_op    = CSR_OP_CSRRC;
							id_csr_imm   = 1'b1;
							id_csr_wdata = {27'h0, id_rs1};
						end

						default: begin
							id_rf_we     = 1'b0;
							id_csr_op    = CSR_OP_NONE;
						end
					endcase
				end

				default: begin end
				endcase
			end
		end
	end

	// 冒险判断只需要 opcode 级别的信息，不经过完整的 Z/M/CSR 主译码。
	assign hazard_is_branch = ifid_valid && (id_opcode == OPC_BRANCH);
	assign hazard_is_jalr   = ifid_valid && (id_opcode == OPC_JALR);

	always_comb begin
		hazard_uses_rs1 = 1'b0;
		hazard_uses_rs2 = 1'b0;
		if (ifid_valid) begin
			case (id_opcode)
				OPC_JALR,
				OPC_OPIMM,
				OPC_LOAD: begin
					hazard_uses_rs1 = 1'b1;
				end

				OPC_BRANCH,
				OPC_STORE,
				OPC_OP: begin
					hazard_uses_rs1 = 1'b1;
					hazard_uses_rs2 = 1'b1;
				end

				OPC_SYSTEM: begin
					// CSRRW/CSRRS/CSRRC 使用寄存器 rs1；立即数 CSR 使用 zimm。
					if ((id_funct3 != 3'b000) && !id_funct3[2])
						hazard_uses_rs1 = 1'b1;
				end

				default: begin end
			endcase
		end
	end

	assign load_use_ex1_hazard = ifid_valid && idex1_valid && idex1_rf_we &&
							 (idex1_wb_sel == WB_SRC_MEM) && (idex1_rd != 5'h0) &&
							 ((hazard_uses_rs1 && (id_rs1 == idex1_rd)) ||
							  (hazard_uses_rs2 && (id_rs2 == idex1_rd)));

	assign load_use_ex2_hazard = ifid_valid && ex1ex2_valid && ex1ex2_rf_we &&
								(ex1ex2_wb_sel == WB_SRC_MEM) && (ex1ex2_rd != 5'h0) &&
								((hazard_uses_rs1 && (id_rs1 == ex1ex2_rd)) ||
								 (hazard_uses_rs2 && (id_rs2 == ex1ex2_rd)));

	assign load_use_hazard = load_use_ex1_hazard || load_use_ex2_hazard;
	// 普通 ALU 结果可以走 EX2 -> EX1 快速旁路，其余结果等到 EX2/MEM。
	assign slow_result_ex1_hazard = ifid_valid && idex1_valid && idex1_rf_we &&
								 (idex1_rd != 5'h0) &&
								 !idex1_can_forward_to_ex1ex2 &&
								 ((hazard_uses_rs1 && (id_rs1 == idex1_rd)) ||
								  (hazard_uses_rs2 && (id_rs2 == idex1_rd)));
	assign m_issue_hazard = idex1_valid && idex1_is_m_ext;

	assign pc_ex1_hazard = ifid_valid && idex1_valid && idex1_rf_we &&
						 (idex1_rd != 5'h0) &&
						 (((hazard_is_branch || hazard_is_jalr) && (id_rs1 == idex1_rd)) ||
						  (hazard_is_branch && (id_rs2 == idex1_rd)));

	assign pc_ex2_hazard = ifid_valid && ex1ex2_valid && ex1ex2_rf_we &&
						 (ex1ex2_rd != 5'h0) &&
						 (((hazard_is_branch || hazard_is_jalr) && (id_rs1 == ex1ex2_rd)) ||
						  (hazard_is_branch && (id_rs2 == ex1ex2_rd)));

	assign pc_mem_hazard = ifid_valid && ex2mem_valid && ex2mem_rf_we &&
					  (ex2mem_rd != 5'h0) &&
					  (((hazard_is_branch || hazard_is_jalr) && (id_rs1 == ex2mem_rd)) ||
					   (hazard_is_branch && (id_rs2 == ex2mem_rd)));

	assign load_in_mem = ex2mem_valid && ex2mem_mem_req && !ex2mem_mem_write;

	// perip_bridge 的读数据输出再打一拍后，所有 load 在 EX/MEM 保持 2 拍，
	// 第 3 拍再把稳定的 perip_rdata 捕获进 MEM/WB。
	assign mem_load_stall = ex2mem_is_load && (mem_load_wait_cnt < LOAD_WAIT_CYCLES);

	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst)
			mem_stall_flag <= 1'b0;
		else
			mem_stall_flag <= mem_load_stall;
	end

	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst)
			mem_load_wait_cnt <= 2'd0;
		else if (!ex2mem_is_load)
			mem_load_wait_cnt <= 2'd0;
		else if (mem_load_wait_cnt < LOAD_WAIT_CYCLES)
			mem_load_wait_cnt <= mem_load_wait_cnt + 2'd1;
		else
			mem_load_wait_cnt <= 2'd0;
	end

	// ID/EX 流水寄存器：遇到 load-use hazard 或 EX/MEM load stall 时保持。
	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			idex1_valid         <= 1'b0;
			idex1_pc            <= 32'h0;
			idex1_instr         <= NOP_INSTR;
			idex1_rs1           <= 5'h0;
			idex1_rs2           <= 5'h0;
			idex1_rs1_val       <= 32'h0;
			idex1_rs2_val       <= 32'h0;
			idex1_uses_rs1      <= 1'b0;
			idex1_uses_rs2      <= 1'b0;
			idex1_rd            <= 5'h0;
			idex1_funct3        <= 3'h0;
			idex1_mul_helper    <= 1'b0;
			idex1_mul_helper_ra <= 32'h0;
			idex1_mul_helper_lhs <= 32'h0;
			idex1_mul_helper_rhs <= 32'h0;
			idex1_imm           <= 32'h0;
			idex1_rf_we         <= 1'b0;
			idex1_wb_sel        <= WB_SRC_ALU;
			idex1_alu_src_a_sel <= ALU_SRC_A_RS1;
			idex1_alu_src_b_sel <= ALU_SRC_B_RS2;
			idex1_alu_op        <= ALU_ADD;
			idex1_pc_sel        <= PC_SRC_PC4;
			idex1_mem_req       <= 1'b0;
			idex1_mem_write     <= 1'b0;
			idex1_mem_mask      <= MEM_MASK_WORD;
			idex1_csr_op        <= CSR_OP_NONE;
			idex1_csr_imm       <= 1'b0;
			idex1_csr_addr      <= 12'h0;
			idex1_csr_wdata     <= 32'h0;
			idex1_is_ecall      <= 1'b0;
			idex1_is_mret       <= 1'b0;
			idex1_is_m_ext      <= 1'b0;
			idex1_m_op          <= M_OP_NONE;
			idex1_is_z_light    <= 1'b0;
			idex1_z_op          <= ZOP_NONE;
			idex1_z_shamt       <= 5'h0;
			idex1_fwd_rs1_from_ex2 <= 1'b0;
			idex1_fwd_rs1_from_mem <= 1'b0;
			idex1_fwd_rs2_from_ex2 <= 1'b0;
			idex1_fwd_rs2_from_mem <= 1'b0;
			idex1_fwd_rs1_from_wb <= 1'b0;
			idex1_fwd_rs2_from_wb <= 1'b0;
		end else if (mem_load_stall || m_stall || stall_z_b_small) begin
			// hold IDEX - memory read stall
		end else if (ex2_pc_redirect || load_use_ex1_hazard || load_use_ex2_hazard ||
					 slow_result_ex1_hazard ||
					 pc_ex1_hazard || pc_ex2_hazard || pc_mem_hazard || m_issue_hazard) begin
			// valid=0 表示气泡；payload 仍然写入，避免复杂冒险条件成为宽寄存器的 CE。
			idex1_valid         <= 1'b0;
			idex1_pc            <= ifid_pc;
			idex1_instr         <= ifid_instr;
			idex1_rs1           <= id_rs1;
			idex1_rs2           <= id_rs2;
			idex1_rs1_val       <= id_rs1_val;
			idex1_rs2_val       <= id_rs2_val;
			idex1_uses_rs1      <= id_uses_rs1;
			idex1_uses_rs2      <= id_uses_rs2;
			idex1_rd            <= id_rd;
			idex1_funct3        <= id_funct3;
			idex1_mul_helper    <= 1'b0;
			idex1_mul_helper_ra <= 32'h0;
			idex1_mul_helper_lhs <= 32'h0;
			idex1_mul_helper_rhs <= 32'h0;
			idex1_imm           <= id_imm;
			idex1_rf_we         <= id_rf_we;
			idex1_wb_sel        <= id_wb_sel;
			idex1_alu_src_a_sel <= id_alu_src_a_sel;
			idex1_alu_src_b_sel <= id_alu_src_b_sel;
			idex1_alu_op        <= id_alu_op;
			idex1_pc_sel        <= id_pc_sel;
			idex1_mem_req       <= id_mem_req;
			idex1_mem_write     <= id_mem_write;
			idex1_mem_mask      <= id_mem_mask;
			idex1_csr_op        <= id_csr_op;
			idex1_csr_imm       <= id_csr_imm;
			idex1_csr_addr      <= id_csr_addr;
			idex1_csr_wdata     <= id_csr_wdata;
			idex1_is_ecall      <= id_is_ecall;
			idex1_is_mret       <= id_is_mret;
			idex1_is_m_ext      <= id_is_m_ext;
			idex1_m_op          <= id_m_op;
			idex1_is_z_light    <= id_is_z_light;
			idex1_z_op          <= id_z_op;
			idex1_z_shamt       <= id_z_shamt;
			idex1_fwd_rs1_from_ex2 <= id_fwd_rs1_from_ex2;
			idex1_fwd_rs1_from_mem <= id_fwd_rs1_from_mem;
			idex1_fwd_rs2_from_ex2 <= id_fwd_rs2_from_ex2;
			idex1_fwd_rs2_from_mem <= id_fwd_rs2_from_mem;
			idex1_fwd_rs1_from_wb <= id_fwd_rs1_from_wb;
			idex1_fwd_rs2_from_wb <= id_fwd_rs2_from_wb;
		end else if (id_mul_helper_hit) begin
			idex1_valid         <= 1'b1;
			idex1_pc            <= ifid_pc;
			idex1_instr         <= ifid_instr;
			idex1_rs1           <= 5'h0;
			idex1_rs2           <= 5'h0;
			idex1_rs1_val       <= 32'h0;
			idex1_rs2_val       <= 32'h0;
			idex1_uses_rs1      <= 1'b0;
			idex1_uses_rs2      <= 1'b0;
			idex1_rd            <= 5'd10;
			idex1_funct3        <= 3'h0;
			idex1_mul_helper    <= 1'b1;
			idex1_mul_helper_ra <= id_mul_helper_ra;
			idex1_mul_helper_lhs <= id_mul_helper_lhs;
			idex1_mul_helper_rhs <= id_mul_helper_rhs;
			idex1_imm           <= 32'h0;
			idex1_rf_we         <= 1'b1;
			idex1_wb_sel        <= WB_SRC_ALU;
			idex1_alu_src_a_sel <= ALU_SRC_A_RS1;
			idex1_alu_src_b_sel <= ALU_SRC_B_RS2;
			idex1_alu_op        <= ALU_ADD;
			idex1_pc_sel        <= PC_SRC_PC4;
			idex1_mem_req       <= 1'b0;
			idex1_mem_write     <= 1'b0;
			idex1_mem_mask      <= MEM_MASK_WORD;
			idex1_csr_op        <= CSR_OP_NONE;
			idex1_csr_imm       <= 1'b0;
			idex1_csr_addr      <= 12'h0;
			idex1_csr_wdata     <= 32'h0;
			idex1_is_ecall      <= 1'b0;
			idex1_is_mret       <= 1'b0;
			idex1_is_m_ext      <= 1'b0;
			idex1_m_op          <= M_OP_NONE;
			idex1_is_z_light    <= 1'b0;
			idex1_z_op          <= ZOP_NONE;
			idex1_z_shamt       <= 5'h0;
			idex1_fwd_rs1_from_ex2 <= 1'b0;
			idex1_fwd_rs1_from_mem <= 1'b0;
			idex1_fwd_rs2_from_ex2 <= 1'b0;
			idex1_fwd_rs2_from_mem <= 1'b0;
			idex1_fwd_rs1_from_wb <= 1'b0;
			idex1_fwd_rs2_from_wb <= 1'b0;
		end else begin
			idex1_valid         <= ifid_valid;
			idex1_pc            <= ifid_pc;
			idex1_instr         <= ifid_instr;
			idex1_rs1           <= id_rs1;
			idex1_rs2           <= id_rs2;
			idex1_rs1_val       <= id_rs1_val;
			idex1_rs2_val       <= id_rs2_val;
			idex1_uses_rs1      <= id_uses_rs1;
			idex1_uses_rs2      <= id_uses_rs2;
			idex1_rd            <= id_rd;
			idex1_funct3        <= id_funct3;
			idex1_mul_helper    <= 1'b0;
			idex1_mul_helper_ra <= 32'h0;
			idex1_mul_helper_lhs <= 32'h0;
			idex1_mul_helper_rhs <= 32'h0;
			idex1_imm           <= id_imm;
			idex1_rf_we         <= id_rf_we;
			idex1_wb_sel        <= id_wb_sel;
			idex1_alu_src_a_sel <= id_alu_src_a_sel;
			idex1_alu_src_b_sel <= id_alu_src_b_sel;
			idex1_alu_op        <= id_alu_op;
			idex1_pc_sel        <= id_pc_sel;
			idex1_mem_req       <= id_mem_req;
			idex1_mem_write     <= id_mem_write;
			idex1_mem_mask      <= id_mem_mask;
			idex1_csr_op        <= id_csr_op;
			idex1_csr_imm       <= id_csr_imm;
			idex1_csr_addr      <= id_csr_addr;
			idex1_csr_wdata     <= id_csr_wdata;
			idex1_is_ecall      <= id_is_ecall;
			idex1_is_mret       <= id_is_mret;
			idex1_is_m_ext      <= id_is_m_ext;
			idex1_m_op          <= id_m_op;
			idex1_is_z_light    <= id_is_z_light;
			idex1_z_op          <= id_z_op;
			idex1_z_shamt       <= id_z_shamt;
			idex1_fwd_rs1_from_ex2 <= id_fwd_rs1_from_ex2;
			idex1_fwd_rs1_from_mem <= id_fwd_rs1_from_mem;
			idex1_fwd_rs2_from_ex2 <= id_fwd_rs2_from_ex2;
			idex1_fwd_rs2_from_mem <= id_fwd_rs2_from_mem;
			idex1_fwd_rs1_from_wb <= id_fwd_rs1_from_wb;
			idex1_fwd_rs2_from_wb <= id_fwd_rs2_from_wb;
		end
	end

	// EX1 前递：EX2 -> EX1、MEM -> EX1、WB -> EX1。
	// WB -> ID 的同拍旁路位于 id_rs1_val/id_rs2_val 组合逻辑中。
	always_comb begin
		ex1_rs1_val = idex1_rs1_val;
		if (idex1_fwd_rs1_from_ex2) begin
			ex1_rs1_val = ex2_alu_y;
		end else if (idex1_fwd_rs1_from_mem) begin
			ex1_rs1_val = ex2mem_wb_data;
		end else if (idex1_fwd_rs1_from_wb) begin
			ex1_rs1_val = memwb_wdata;
		end

		ex1_rs2_val = idex1_rs2_val;
		if (idex1_fwd_rs2_from_ex2) begin
			ex1_rs2_val = ex2_alu_y;
		end else if (idex1_fwd_rs2_from_mem) begin
			ex1_rs2_val = ex2mem_wb_data;
		end else if (idex1_fwd_rs2_from_wb) begin
			ex1_rs2_val = memwb_wdata;
		end
	end

	// Resolve the branch in EX1, after operand forwarding, and register the
	// one-bit decision so the 32-bit comparator is not in the EX2 -> PC path.
	always_comb begin
		ex1_cmp_eq          = 1'b0;
		ex1_cmp_lt_signed   = 1'b0;
		ex1_cmp_lt_unsigned = 1'b0;
		ex1_br_take         = 1'b0;
		if (idex1_valid && (idex1_pc_sel == PC_SRC_BRANCH)) begin
			ex1_cmp_eq          = (idex1_rs1_val == idex1_rs2_val);
			ex1_cmp_lt_signed   = ($signed(idex1_rs1_val) < $signed(idex1_rs2_val));
			ex1_cmp_lt_unsigned = (idex1_rs1_val < idex1_rs2_val);

			unique case (idex1_funct3)
				3'b000: ex1_br_take = ex1_cmp_eq;
				3'b001: ex1_br_take = !ex1_cmp_eq;
				3'b100: ex1_br_take = ex1_cmp_lt_signed;
				3'b101: ex1_br_take = !ex1_cmp_lt_signed;
				3'b110: ex1_br_take = ex1_cmp_lt_unsigned;
				3'b111: ex1_br_take = !ex1_cmp_lt_unsigned;
				default: ex1_br_take = 1'b0;
			endcase
		end
	end
	
	assign ex1_alu_a = (idex1_alu_src_a_sel == ALU_SRC_A_PC) ? idex1_pc : ex1_rs1_val;

	always_comb begin
		case (idex1_alu_src_b_sel)
			ALU_SRC_B_RS2:   ex1_alu_b = ex1_rs2_val;
			ALU_SRC_B_IMM_I: ex1_alu_b = idex1_imm;
			ALU_SRC_B_IMM_S: ex1_alu_b = idex1_imm;
			ALU_SRC_B_IMM_U: ex1_alu_b = idex1_imm;
			default:         ex1_alu_b = ex1_rs2_val;
		endcase
	end

	// EX1/EX2 pipeline register: EX1 resolves forwarding and operand selection.
	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			ex1ex2_valid <= 1'b0;
			ex1ex2_pc <= 32'h0;
			ex1ex2_instr <= NOP_INSTR;
			ex1ex2_rs1 <= 5'h0;
			ex1ex2_rs2 <= 5'h0;
			ex1ex2_rs1_val <= 32'h0;
			ex1ex2_rs2_val <= 32'h0;
			ex1ex2_alu_a <= 32'h0;
			ex1ex2_alu_b <= 32'h0;
			ex1ex2_store_data <= 32'h0;
			ex1ex2_rd <= 5'h0;
			ex1ex2_imm <= 32'h0;
			ex1ex2_funct3 <= 3'h0;
			ex1ex2_br_take <= 1'b0;
			ex1ex2_mul_helper <= 1'b0;
			ex1ex2_mul_helper_ra <= 32'h0;
			ex1ex2_mul_helper_lhs <= 32'h0;
			ex1ex2_mul_helper_rhs <= 32'h0;
			ex1ex2_rf_we <= 1'b0;
			ex1ex2_wb_sel <= WB_SRC_ALU;
			ex1ex2_alu_op <= ALU_ADD;
			ex1ex2_pc_sel <= PC_SRC_PC4;
			ex1ex2_mem_req <= 1'b0;
			ex1ex2_mem_write <= 1'b0;
			ex1ex2_mem_mask <= MEM_MASK_WORD;
			ex1ex2_csr_op <= CSR_OP_NONE;
			ex1ex2_csr_imm <= 1'b0;
			ex1ex2_csr_addr <= 12'h0;
			ex1ex2_csr_wdata <= 32'h0;
			ex1ex2_is_ecall <= 1'b0;
			ex1ex2_is_mret <= 1'b0;
			ex1ex2_is_m_ext <= 1'b0;
			ex1ex2_m_op <= M_OP_NONE;
			ex1ex2_is_z_light <= 1'b0;
			ex1ex2_z_op <= ZOP_NONE;
			ex1ex2_z_shamt <= 5'h0;
		end else if (hold_ex1ex2) begin
			// Hold EX2 while the back end is busy.
		end else if (ex2_pc_redirect) begin
			ex1ex2_valid <= 1'b0;
		end else begin
			ex1ex2_valid <= idex1_valid;
			ex1ex2_pc <= idex1_pc;
			ex1ex2_instr <= idex1_instr;
			ex1ex2_rs1 <= idex1_rs1;
			ex1ex2_rs2 <= idex1_rs2;
			ex1ex2_rs1_val <= ex1_rs1_val;
			ex1ex2_rs2_val <= ex1_rs2_val;
			ex1ex2_alu_a <= ex1_alu_a;
			ex1ex2_alu_b <= ex1_alu_b;
			ex1ex2_store_data <= idex1_mem_write ? ex1_rs2_val : 32'h0;
			ex1ex2_rd <= idex1_rd;
			ex1ex2_imm <= idex1_imm;
			ex1ex2_funct3 <= idex1_funct3;
			ex1ex2_br_take <= ex1_br_take;
			ex1ex2_mul_helper <= idex1_mul_helper;
			ex1ex2_mul_helper_ra <= idex1_mul_helper_ra;
			ex1ex2_mul_helper_lhs <= idex1_mul_helper_lhs;
			ex1ex2_mul_helper_rhs <= idex1_mul_helper_rhs;
			ex1ex2_rf_we <= idex1_rf_we;
			ex1ex2_wb_sel <= idex1_wb_sel;
			ex1ex2_alu_op <= idex1_alu_op;
			ex1ex2_pc_sel <= idex1_pc_sel;
			ex1ex2_mem_req <= idex1_mem_req;
			ex1ex2_mem_write <= idex1_mem_write;
			ex1ex2_mem_mask <= idex1_mem_mask;
			ex1ex2_csr_op <= idex1_csr_op;
			ex1ex2_csr_imm <= idex1_csr_imm;
			ex1ex2_csr_addr <= idex1_csr_addr;
			ex1ex2_csr_wdata <= idex1_csr_wdata;
			ex1ex2_is_ecall <= idex1_is_ecall;
			ex1ex2_is_mret <= idex1_is_mret;
			ex1ex2_is_m_ext <= idex1_is_m_ext;
			ex1ex2_m_op <= idex1_m_op;
			ex1ex2_is_z_light <= idex1_is_z_light;
			ex1ex2_z_op <= idex1_z_op;
			ex1ex2_z_shamt <= idex1_z_shamt;
		end
	end

	assign ex2_rs1_val = ex1ex2_rs1_val;
	assign ex2_rs2_val = ex1ex2_rs2_val;

	assign ex2_br_take = ex1ex2_br_take;

	// 所有改变 PC 的东西，最后都归到 ex2_pc_redirect + ex2_pc_target
	always_comb begin
		if (ex2_trap_redirect) begin
			ex2_pc_target = ex2_trap_target;
		end else if (ex1ex2_mul_helper) begin
			ex2_pc_target = ex1ex2_mul_helper_ra;
		end else begin
			case (ex1ex2_pc_sel)
				PC_SRC_BRANCH: ex2_pc_target = ex2_br_take ? ex2_pc_plus_imm : ex2_pc4;
				PC_SRC_JAL:    ex2_pc_target = ex2_pc_plus_imm;
				PC_SRC_JALR:   ex2_pc_target = ex2_jalr_target;
				default:       ex2_pc_target = ex2_pc4;
			endcase
		end
	end

	assign ex2_z_wb_data = ex2_z_supported ? ex2_z_result : 32'h0;

	always_comb begin
		if (ex1ex2_mul_helper) begin
			ex2_wb_data = ex2_mul_helper_result;
		end else if (ex1ex2_is_m_ext) begin
			ex2_wb_data = ex2_m_result;
		end else begin
			unique case (ex1ex2_wb_sel)
				WB_SRC_Z:     ex2_wb_data = ex2_is_z_b_small ? 32'h0 : ex2_z_wb_data;
				WB_SRC_CSR:   ex2_wb_data = ex2_csr_rdata;
				WB_SRC_PC4:   ex2_wb_data = ex2_pc4;
				WB_SRC_IMM_U: ex2_wb_data = ex1ex2_imm;
				WB_SRC_ALU:   ex2_wb_data = ex2_alu_y;
				default:      ex2_wb_data = ex2_alu_y;
			endcase
		end
	end

	always_comb begin
		unique case (ex1ex2_csr_addr)
			CSR_MSTATUS: ex2_csr_rdata = csr_mstatus;
			CSR_MTVEC:   ex2_csr_rdata = csr_mtvec;
			CSR_MEPC:    ex2_csr_rdata = csr_mepc;
			CSR_MCAUSE:  ex2_csr_rdata = csr_mcause;
			CSR_MSCRATCH: ex2_csr_rdata = csr_mscratch;
			default:     ex2_csr_rdata = 32'h0;
		endcase
	end
	
	always_comb begin
		ex2_csr_we    = 1'b0;
		ex2_csr_wdata = ex2_csr_rdata;

		unique case (ex1ex2_csr_op)
			CSR_OP_CSRRW: begin
				ex2_csr_we    = 1'b1;
				ex2_csr_wdata = ex1ex2_csr_imm ? ex1ex2_csr_wdata : ex1ex2_rs1_val;
			end

			CSR_OP_CSRRS: begin
				// rs1=x0 或 uimm=0 时，只读不写
				ex2_csr_we    = csr_write_operand_nonzero;
				ex2_csr_wdata = ex2_csr_rdata | (ex1ex2_csr_imm ? ex1ex2_csr_wdata : ex1ex2_rs1_val);
			end

			CSR_OP_CSRRC: begin
				// rs1=x0 或 uimm=0 时，只读不写
				ex2_csr_we    = csr_write_operand_nonzero;
				ex2_csr_wdata = ex2_csr_rdata & ~(ex1ex2_csr_imm ? ex1ex2_csr_wdata : ex1ex2_rs1_val);
			end

			default: begin
				ex2_csr_we    = 1'b0;
				ex2_csr_wdata = ex2_csr_rdata;
			end
		endcase
	end

	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			z_b_small_pending_q     <= 1'b0;
			z_b_small_op_q          <= ZOP_NONE;
			z_b_small_rd_q          <= 5'h0;
			z_b_small_rf_we_q       <= 1'b0;
			z_b_small_wb_sel_q      <= WB_SRC_Z;
			z_b_small_pc_q          <= 32'h0;
			z_b_small_partial_q     <= 32'h0;
			z_b_small_rs1_q         <= 32'h0;
			z_b_small_rs2_q         <= 32'h0;
			z_b_small_shamt_hi_q    <= 2'b00;
			z_b_small_signed_lt_q   <= 1'b0;
			z_b_small_unsigned_lt_q <= 1'b0;
		end else if (z_b_small_start) begin
			z_b_small_pending_q     <= 1'b1;
			z_b_small_op_q          <= ex1ex2_z_op;
			z_b_small_rd_q          <= ex1ex2_rd;
			z_b_small_rf_we_q       <= ex1ex2_rf_we;
			z_b_small_wb_sel_q      <= ex1ex2_wb_sel;
			z_b_small_pc_q          <= ex1ex2_pc;
			z_b_small_partial_q     <= z_b_small_stage1_partial;
			z_b_small_rs1_q         <= ex1ex2_rs1_val;
			z_b_small_rs2_q         <= ex1ex2_rs2_val;
			z_b_small_shamt_hi_q    <= z_b_small_eff_shamt[4:3];
			z_b_small_signed_lt_q   <= ($signed(ex1ex2_rs1_val) < $signed(ex1ex2_rs2_val));
			z_b_small_unsigned_lt_q <= (ex1ex2_rs1_val < ex1ex2_rs2_val);
		end else if (z_b_small_pending_q && !mem_load_stall && !m_stall) begin
			z_b_small_pending_q <= 1'b0;
		end
	end

	always_ff @(posedge cpu_clk) begin
		if (cpu_rst) begin
			ex2mem_valid      <= 1'b0;
			ex2mem_alu_y      <= 32'h0;
			ex2mem_store_data <= 32'h0;
			ex2mem_store_wstrb <= 4'h0;
			ex2mem_is_dram    <= 1'b0;
			ex2mem_rd         <= 5'h0;
			ex2mem_funct3     <= 3'h0;
			ex2mem_wb_data    <= 32'h0;
			ex2mem_rf_we      <= 1'b0;
			ex2mem_wb_sel     <= WB_SRC_ALU;
			ex2mem_mem_req    <= 1'b0;
			ex2mem_mem_write  <= 1'b0;
			ex2mem_mem_mask   <= MEM_MASK_WORD;
			ex2mem_pc         <= 32'h0;
			ex2mem_addr_base  <= 32'h0;
			ex2mem_addr_off   <= 32'h0;
		end else if (mem_load_stall) begin
			// hold EXMEM - memory read stall
		end else if (m_stall) begin
			ex2mem_valid      <= 1'b0;
			ex2mem_alu_y      <= 32'h0;
			ex2mem_store_data <= 32'h0;
			ex2mem_store_wstrb <= 4'h0;
			ex2mem_is_dram    <= 1'b0;
			ex2mem_rd         <= 5'h0;
			ex2mem_funct3     <= 3'h0;
			ex2mem_wb_data    <= 32'h0;
			ex2mem_rf_we      <= 1'b0;
			ex2mem_wb_sel     <= WB_SRC_ALU;
			ex2mem_mem_req    <= 1'b0;
			ex2mem_mem_write  <= 1'b0;
			ex2mem_mem_mask   <= MEM_MASK_WORD;
			ex2mem_pc         <= 32'h0;
			ex2mem_addr_base  <= 32'h0;
			ex2mem_addr_off   <= 32'h0;
		end else if (z_b_small_pending_q) begin
			ex2mem_valid      <= 1'b1;
			ex2mem_alu_y      <= 32'h0;
			ex2mem_store_data <= 32'h0;
			ex2mem_store_wstrb <= 4'h0;
			ex2mem_is_dram    <= 1'b0;
			ex2mem_rd         <= z_b_small_rd_q;
			ex2mem_funct3     <= 3'h0;
			ex2mem_wb_data    <= z_b_small_final_result;
			ex2mem_rf_we      <= z_b_small_rf_we_q;
			ex2mem_wb_sel     <= z_b_small_wb_sel_q;
			ex2mem_mem_req    <= 1'b0;
			ex2mem_mem_write  <= 1'b0;
			ex2mem_mem_mask   <= MEM_MASK_WORD;
			ex2mem_pc         <= z_b_small_pc_q;
			ex2mem_addr_base  <= 32'h0;
			ex2mem_addr_off   <= 32'h0;
		end else if (z_b_small_start) begin
			ex2mem_valid      <= 1'b0;
			ex2mem_alu_y      <= 32'h0;
			ex2mem_store_data <= 32'h0;
			ex2mem_store_wstrb <= 4'h0;
			ex2mem_is_dram    <= 1'b0;
			ex2mem_rd         <= 5'h0;
			ex2mem_funct3     <= 3'h0;
			ex2mem_wb_data    <= 32'h0;
			ex2mem_rf_we      <= 1'b0;
			ex2mem_wb_sel     <= WB_SRC_ALU;
			ex2mem_mem_req    <= 1'b0;
			ex2mem_mem_write  <= 1'b0;
			ex2mem_mem_mask   <= MEM_MASK_WORD;
			ex2mem_pc         <= 32'h0;
			ex2mem_addr_base  <= 32'h0;
			ex2mem_addr_off   <= 32'h0;
		end else begin
			ex2mem_valid      <= ex1ex2_valid;
			ex2mem_alu_y      <= ex2_alu_y;
			ex2mem_store_data <= ex2_store_data_aligned;
			ex2mem_store_wstrb <= ex2_store_wstrb;
			ex2mem_is_dram    <= ex2_is_dram;
			ex2mem_rd         <= ex1ex2_rd;
			ex2mem_funct3     <= ex1ex2_funct3;
			ex2mem_wb_data    <= ex2_wb_data;
			ex2mem_rf_we      <= ex1ex2_rf_we;
			ex2mem_wb_sel     <= ex1ex2_wb_sel;
			ex2mem_mem_req    <= ex1ex2_mem_req;
			ex2mem_mem_write  <= ex1ex2_mem_write;
			ex2mem_mem_mask   <= ex1ex2_mem_mask;
			ex2mem_pc         <= ex1ex2_pc;
			ex2mem_addr_base  <= ex1ex2_alu_a;
			ex2mem_addr_off   <= ex1ex2_alu_b;
		end
	end

	always_comb begin
		case (ex2mem_funct3)
			3'b000: begin
				case (ex2mem_alu_y[1:0])
					2'b00: mem_load_data = {{24{perip_rdata[7]}}, perip_rdata[7:0]};
					2'b01: mem_load_data = {{24{perip_rdata[15]}}, perip_rdata[15:8]};
					2'b10: mem_load_data = {{24{perip_rdata[23]}}, perip_rdata[23:16]};
					default: mem_load_data = {{24{perip_rdata[31]}}, perip_rdata[31:24]};
				endcase
			end
			3'b001: mem_load_data = ex2mem_alu_y[1] ? {{16{perip_rdata[31]}}, perip_rdata[31:16]} : {{16{perip_rdata[15]}}, perip_rdata[15:0]};
			3'b010: mem_load_data = perip_rdata;
			3'b100: begin
				case (ex2mem_alu_y[1:0])
					2'b00: mem_load_data = {24'h0, perip_rdata[7:0]};
					2'b01: mem_load_data = {24'h0, perip_rdata[15:8]};
					2'b10: mem_load_data = {24'h0, perip_rdata[23:16]};
					default: mem_load_data = {24'h0, perip_rdata[31:24]};
				endcase
			end
			3'b101: mem_load_data = ex2mem_alu_y[1] ? {16'h0, perip_rdata[31:16]} : {16'h0, perip_rdata[15:0]};
			default: mem_load_data = perip_rdata;
		endcase
	end

	assign mem_wb_data = (ex2mem_wb_sel == WB_SRC_MEM) ? mem_load_data : ex2mem_wb_data;

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
			memwb_valid <= ex2mem_valid;
			memwb_wdata <= mem_wb_data;
			memwb_rd    <= ex2mem_rd;
			memwb_rf_we <= ex2mem_rf_we;
			memwb_pc    <= ex2mem_pc;
		end
	end

	always_ff @(posedge cpu_clk or posedge cpu_rst) begin
		if (cpu_rst) begin
			csr_mstatus <= 32'h0000_1800;
			csr_mtvec   <= 32'h0000_0000;
			csr_mepc    <= 32'h0000_0000;
			csr_mcause  <= 32'h0000_0000;
			csr_mscratch <= 32'h0000_0000;
		end else if (ex2_trap_enter) begin
			// trap 进入：MPIE <= MIE, MIE <= 0, MPP <= M 模式
			csr_mstatus[7]      <= csr_mstatus[3];
			csr_mstatus[3]      <= 1'b0;
			csr_mstatus[12:11]  <= 2'b11;
			csr_mepc           <= ex1ex2_pc;
			csr_mcause         <= 32'd11;         // ECALL from M-mode
		end else if (ex2_trap_return) begin
			// mret 返回：MIE <= MPIE, MPIE <= 1, MPP 清零
			csr_mstatus[3]      <= csr_mstatus[7];
			csr_mstatus[7]      <= 1'b1;
			csr_mstatus[12:11]  <= 2'b00;
		end else if (ex1ex2_valid && !mem_load_stall && ex2_csr_we) begin
			unique case (ex1ex2_csr_addr)
				CSR_MSTATUS: csr_mstatus <= ex2_csr_wdata;
				CSR_MTVEC:   csr_mtvec   <= ex2_csr_wdata;
				CSR_MEPC:    csr_mepc    <= ex2_csr_wdata;
				CSR_MCAUSE:  csr_mcause  <= ex2_csr_wdata;
				CSR_MSCRATCH: csr_mscratch <= ex2_csr_wdata;
				default: begin end
			endcase
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
