`timescale 1ns / 1ps

module tb_perf_load_use;
    // load-use 冒险性能测试。
    // 构造连续 load / use 相关链，统计暂停次数和 CPI，专门观察 load 返回路径的代价。

    // 200 MHz CPU clock: 5 ns period
    localparam real CPU_CLK_PERIOD_NS = 5.0;

    // 固定采样周期，避免程序末尾自循环导致 timeout
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

    // 简易数据存储器
    // 只用于本 load-use 性能测试
    logic [31:0] dmem [0:255];

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
        $display("[LOAD-PERF] Reset released. CPU clock = 200 MHz.");
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

    function automatic logic [31:0] enc_s(
        input int imm,
        input int rs2,
        input int rs1,
        input logic [2:0] funct3
    );
        logic [11:0] imm12;
        logic [4:0]  rs2_5;
        logic [4:0]  rs1_5;
        begin
            imm12 = imm[11:0];
            rs2_5 = rs2[4:0];
            rs1_5 = rs1[4:0];

            enc_s = {
                imm12[11:5],
                rs2_5,
                rs1_5,
                funct3,
                imm12[4:0],
                7'b0100011
            };
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
            1. 使用 x20 作为数据存储器基地址；
            2. 循环中执行 lw；
            3. lw 后紧跟 add，立即使用 lw 读出的 x2；
            4. 统计 load-use stall 和 mem-load stall。
        */

        // 0x8000_0000:
        imem[0]  = enc_i(0,   0, 3'b000, 20, 7'b0010011); // addi x20, x0, 0      ; dmem base
        imem[1]  = enc_i(100, 0, 3'b000, 10, 7'b0010011); // addi x10, x0, 100    ; loop count
        imem[2]  = enc_i(0,   0, 3'b000, 11, 7'b0010011); // addi x11, x0, 0      ; sum = 0

        // load_loop:
        imem[3]  = enc_i(0, 20, 3'b010, 2, 7'b0000011);   // lw   x2, 0(x20)
        imem[4]  = enc_r(7'b0000000, 2, 11, 3'b000, 11);  // add  x11, x11, x2    ; load-use
        imem[5]  = enc_i(-1, 10, 3'b000, 10, 7'b0010011); // addi x10, x10, -1
        imem[6]  = enc_b(-12, 0, 10, 3'b001);             // bne  x10, x0, load_loop

        // 结束后进入自循环，性能测试通过固定采样周期结束
        imem[7]  = enc_b(0, 0, 0, 3'b000);                // beq x0, x0, 0
    end

    // ----------------------------
    // 数据存储器初始化
    // ----------------------------
    initial begin
        integer i;

        for (i = 0; i < 256; i = i + 1) begin
            dmem[i] = 32'h0000_0001;
        end
    end

    // IROM 读指令
    assign irom_data = imem[irom_addr];

    // ----------------------------
    // 简易数据存储器模型
    // ----------------------------
    // 当前测试只需要 lw/sw 的 word 读写。
    // myCPU 对 load 会产生 mem_load_stall，因此 perip_rdata 需要在访存阶段稳定。
    always_ff @(posedge clk) begin
        if (perip_wen) begin
            dmem[perip_addr[9:2]] <= perip_wdata;
        end
    end

    assign perip_rdata = dmem[perip_addr[9:2]];

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
            $display("[LOAD-PERF] Sampling finished.");
            $display("[LOAD-PERF] sample cycles         = %0d", cycle_count);
            $display("[LOAD-PERF] retired instructions = %0d", instret_count);
            $display("[LOAD-PERF] load-use stalls      = %0d", load_use_stall_count);
            $display("[LOAD-PERF] mem-load stalls      = %0d", mem_load_stall_count);
            $display("[LOAD-PERF] pc redirects         = %0d", pc_redirect_count);
            $display("[LOAD-PERF] CPI                  = %f",
                     instret_count == 0 ? 0.0 : cycle_count * 1.0 / instret_count);
            $display("[LOAD-PERF] time at 200 MHz      = %0f ns",
                     cycle_count * CPU_CLK_PERIOD_NS);
            $finish;
        end
    end

endmodule