`timescale 1ns / 1ps

module tb_perf_alu_stream;

    // 200 MHz CPU clock: 5 ns period
    localparam real CPU_CLK_PERIOD_NS = 5.0;

    // 固定采样周期，避免程序末尾死循环导致 timeout
    localparam int SAMPLE_CYCLES = 2000;

    logic clk;
    logic rst;

    logic [11:0] irom_addr;
    logic [31:0] irom_data;

    logic [31:0] perip_addr;
    logic        perip_wen;
    logic [1:0]  perip_mask;
    logic [31:0] perip_wdata;
    logic [31:0] perip_rdata;

    integer cycle_count;
    integer instret_count;
    integer load_use_stall_count;
    integer mem_load_stall_count;
    integer pc_redirect_count;

    // 简易指令 ROM
    logic [31:0] imem [0:255];

    // ----------------------------
    // DUT: 自研 RV32I CPU
    // ----------------------------
    myCPU dut (
        .cpu_rst    (rst),
        .cpu_clk    (clk),

        .irom_addr  (irom_addr),
        .irom_data  (irom_data),

        .perip_addr (perip_addr),
        .perip_wen  (perip_wen),
        .perip_mask (perip_mask),
        .perip_wdata(perip_wdata),
        .perip_rdata(perip_rdata)
    );

    // ----------------------------
    // 200 MHz clock
    // ----------------------------
    initial begin
        clk = 1'b0;
        forever #(CPU_CLK_PERIOD_NS / 2.0) clk = ~clk;
    end

    // ----------------------------
    // reset
    // ----------------------------
    initial begin
        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        $display("[ALU-PERF] Reset released. CPU clock = 200 MHz.");
    end

    // ----------------------------
    // 指令编码函数
    // ----------------------------
    function automatic logic [31:0] enc_i(
        input int imm,
        input int rs1,
        input logic [2:0] funct3,
        input int rd,
        input logic [6:0] opcode
    );
        logic [11:0] imm12;
        logic [4:0]  rs1_5;
        logic [4:0]  rd_5;
        begin
            imm12 = imm[11:0];
            rs1_5 = rs1[4:0];
            rd_5  = rd[4:0];
            enc_i = {imm12, rs1_5, funct3, rd_5, opcode};
        end
    endfunction

    function automatic logic [31:0] enc_r(
        input logic [6:0] funct7,
        input int rs2,
        input int rs1,
        input logic [2:0] funct3,
        input int rd
    );
        logic [4:0] rs2_5;
        logic [4:0] rs1_5;
        logic [4:0] rd_5;
        begin
            rs2_5 = rs2[4:0];
            rs1_5 = rs1[4:0];
            rd_5  = rd[4:0];
            enc_r = {funct7, rs2_5, rs1_5, funct3, rd_5, 7'b0110011};
        end
    endfunction

    function automatic logic [31:0] enc_b(
        input int imm,
        input int rs2,
        input int rs1,
        input logic [2:0] funct3
    );
        logic [12:0] imm13;
        logic [4:0]  rs2_5;
        logic [4:0]  rs1_5;
        begin
            imm13 = imm[12:0];
            rs2_5 = rs2[4:0];
            rs1_5 = rs1[4:0];

            enc_b = {
                imm13[12],
                imm13[10:5],
                rs2_5,
                rs1_5,
                funct3,
                imm13[4:1],
                imm13[11],
                7'b1100011
            };
        end
    endfunction

    // ----------------------------
    // 指令 ROM 初始化
    // ----------------------------
    initial begin
        integer i;

        // 默认填充 nop: addi x0, x0, 0
        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = enc_i(0, 0, 3'b000, 0, 7'b0010011);
        end

        /*
            测试程序功能：
            x1 = sum
            x2 = loop counter
            循环中连续执行 add/xor/or/and/addi/bne
            重点观察连续 ALU 指令流水线吞吐率
        */

        // 0x8000_0000:
        imem[0]  = enc_i(0,   0, 3'b000, 1, 7'b0010011);  // addi x1, x0, 0
        imem[1]  = enc_i(100, 0, 3'b000, 2, 7'b0010011);  // addi x2, x0, 100
        imem[2]  = enc_i(1,   0, 3'b000, 3, 7'b0010011);  // addi x3, x0, 1
        imem[3]  = enc_i(2,   0, 3'b000, 4, 7'b0010011);  // addi x4, x0, 2
        imem[4]  = enc_i(3,   0, 3'b000, 5, 7'b0010011);  // addi x5, x0, 3

        // alu_loop:
        imem[5]  = enc_r(7'b0000000, 3, 1, 3'b000, 1);    // add x1, x1, x3
        imem[6]  = enc_r(7'b0000000, 5, 4, 3'b000, 6);    // add x6, x4, x5
        imem[7]  = enc_r(7'b0000000, 3, 6, 3'b100, 7);    // xor x7, x6, x3
        imem[8]  = enc_r(7'b0000000, 4, 7, 3'b110, 8);    // or  x8, x7, x4
        imem[9]  = enc_r(7'b0000000, 6, 8, 3'b111, 9);    // and x9, x8, x6
        imem[10] = enc_i(-1,  2, 3'b000, 2, 7'b0010011);  // addi x2, x2, -1

        // bne x2, x0, alu_loop
        // 当前指令地址为 11*4，目标地址为 5*4，offset = -24
        imem[11] = enc_b(-24, 0, 2, 3'b001);              // bne x2, x0, alu_loop

        // 结束后进入自循环，性能测试通过固定采样周期结束，不依赖程序自然结束
        imem[12] = enc_b(0, 0, 0, 3'b000);                // beq x0, x0, 0
    end

    // IROM 读指令
    assign irom_data = imem[irom_addr];

    // 本测试不使用外设读数据
    assign perip_rdata = 32'h0000_0000;

    // ----------------------------
    // 性能统计
    // ----------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    // MEM/WB 阶段 valid 近似表示一条指令完成
    always_ff @(posedge clk) begin
        if (rst) begin
            instret_count <= 0;
        end else if (dut.memwb_valid) begin
            instret_count <= instret_count + 1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            load_use_stall_count <= 0;
        end else if (dut.load_use_hazard) begin
            load_use_stall_count <= load_use_stall_count + 1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            mem_load_stall_count <= 0;
        end else if (dut.mem_load_stall) begin
            mem_load_stall_count <= mem_load_stall_count + 1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            pc_redirect_count <= 0;
        end else if (dut.ex_pc_redirect) begin
            pc_redirect_count <= pc_redirect_count + 1;
        end
    end

    // ----------------------------
    // 固定周期采样结束
    // ----------------------------
    always_ff @(posedge clk) begin
        if (!rst && cycle_count >= SAMPLE_CYCLES) begin
            $display("[ALU-PERF] Sampling finished.");
            $display("[ALU-PERF] sample cycles         = %0d", cycle_count);
            $display("[ALU-PERF] retired instructions = %0d", instret_count);
            $display("[ALU-PERF] load-use stalls      = %0d", load_use_stall_count);
            $display("[ALU-PERF] mem-load stalls      = %0d", mem_load_stall_count);
            $display("[ALU-PERF] pc redirects         = %0d", pc_redirect_count);
            $display("[ALU-PERF] CPI                  = %f",
                     instret_count == 0 ? 0.0 : cycle_count * 1.0 / instret_count);
            $display("[ALU-PERF] time at 200 MHz      = %0f ns",
                     cycle_count * CPU_CLK_PERIOD_NS);
            $finish;
        end
    end

endmodule