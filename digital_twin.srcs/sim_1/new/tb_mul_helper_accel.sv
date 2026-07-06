`timescale 1ns / 1ps

module tb_mul_helper_accel;
    // mul helper 加速路径专项测试。
    // 构造固定 PC 与返回地址场景，检查 helper 命中、跳转和结果写回行为。

    localparam real CPU_CLK_PERIOD_NS = 5.0;
    localparam int  SAMPLE_CYCLES     = 500;

    localparam logic [31:0] RESET_PC                  = 32'h8000_0000;
    localparam logic [31:0] MUL_HELPER_PC            = 32'h8000_1fa8;
    localparam logic [31:0] MUL_HELPER_LOOP004_PC    = 32'h8000_04c4;
    localparam logic [31:0] MUL_HELPER_LOOP004_RA    = 32'h8000_04c8;
    localparam int          BOOT_TO_LOOP004_CALL_OFF = MUL_HELPER_LOOP004_PC - (RESET_PC + 32'd8);
    localparam int          LOOP004_TO_HELPER_OFF    = MUL_HELPER_PC - MUL_HELPER_LOOP004_PC;

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
    integer helper_hit_count;
    integer helper_exec_count;
    integer pc_redirect_count;
    integer x10_write_count;

    logic [31:0] imem [0:4095];

    myCPU dut (
        .cpu_rst     (rst),
        .cpu_clk     (clk),

        .irom_addr   (irom_addr),
        .irom_data   (irom_data),

        .perip_addr  (perip_addr),
        .perip_wen   (perip_wen),
        .perip_mask  (perip_mask),
        .perip_wdata (perip_wdata),
        .perip_rdata (perip_rdata)
    );

    initial begin
        clk = 1'b0;
        forever #(CPU_CLK_PERIOD_NS / 2.0) clk = ~clk;
    end

    initial begin
        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        $display("[MUL-ACCEL] Reset released. CPU clock = 200 MHz.");
    end

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

    function automatic logic [31:0] enc_jal(
        input int rd,
        input int imm
    );
        logic [20:0] imm21;
        begin
            imm21 = imm[20:0];
            enc_jal = {
                imm21[20],
                imm21[10:1],
                imm21[11],
                imm21[19:12],
                rd[4:0],
                7'b1101111
            };
        end
    endfunction

    initial begin
        integer i;

        for (i = 0; i < 4096; i = i + 1) begin
            imem[i] = enc_i(0, 0, 3'b000, 0, 7'b0010011); // nop
        end

        /*
            测试程序模拟当前 myCPU.sv 中 loop004 的真实调用形态：

            0x8000_0000: addi x10, x0, 7
            0x8000_0004: addi x11, x0, 9
            0x8000_0008: jal  x0,  0x8000_04c4   // 跳到 loop004 的 helper 调用点
            0x8000_04c4: jal  x1,  0x8000_1fa8   // 写入 ra = 0x8000_04c8
            0x8000_04c8: beq  x0,  x0, 0         // helper 返回后的停留点

            当前 helper 只有在 ifid_pc == 0x8000_1fa8 且 x1(ra) 为 loop004/loop006
            返回地址时才会命中，因此这里必须保留真实的 jal x1 调用现场，
            不能像旧 tb 那样直接从 reset 附近 jal 到 helper。
        */

        imem[0] = enc_i(7, 0, 3'b000, 10, 7'b0010011);               // addi x10, x0, 7
        imem[1] = enc_i(9, 0, 3'b000, 11, 7'b0010011);               // addi x11, x0, 9
        imem[2] = enc_jal(0, BOOT_TO_LOOP004_CALL_OFF);              // jal x0,  0x8000_04c4
        imem[3] = enc_b(0, 0, 0, 3'b000);                            // safety loop

        imem[MUL_HELPER_LOOP004_PC[13:2]] = enc_jal(1, LOOP004_TO_HELPER_OFF); // jal x1, 0x8000_1fa8
        imem[MUL_HELPER_LOOP004_RA[13:2]] = enc_b(0, 0, 0, 3'b000);             // helper return loop
        imem[MUL_HELPER_PC[13:2]]         = enc_b(0, 0, 0, 3'b000);             // helper miss loop
    end

    assign irom_data   = imem[irom_addr];
    assign perip_rdata = 32'h0000_0000;

    always @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            instret_count <= 0;
        end else if (dut.memwb_valid) begin
            instret_count <= instret_count + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            helper_hit_count <= 0;
        end else if (dut.id_mul_helper_hit) begin
            helper_hit_count <= helper_hit_count + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            helper_exec_count <= 0;
        end else if (dut.idex_valid && dut.idex_mul_helper) begin
            helper_exec_count <= helper_exec_count + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            pc_redirect_count <= 0;
        end else if (dut.ex_pc_redirect) begin
            pc_redirect_count <= pc_redirect_count + 1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            x10_write_count <= 0;
        end else if (dut.memwb_valid &&
                     dut.memwb_rf_we &&
                     dut.memwb_rd == 5'd10) begin
            x10_write_count <= x10_write_count + 1;

            if (dut.memwb_pc == MUL_HELPER_PC && dut.memwb_wdata == 32'd63) begin
                $display("[MUL-ACCEL] PASS: helper wrote x10 with product 63.");
                $display("[MUL-ACCEL] cycles              = %0d", cycle_count);
                $display("[MUL-ACCEL] retired instructions= %0d", instret_count);
                $display("[MUL-ACCEL] helper decode hits  = %0d", helper_hit_count);
                $display("[MUL-ACCEL] helper executes     = %0d", helper_exec_count);
                $display("[MUL-ACCEL] pc redirects        = %0d", pc_redirect_count);
                $display("[MUL-ACCEL] time at 200 MHz     = %0f ns",
                         cycle_count * CPU_CLK_PERIOD_NS);
                $finish;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst && cycle_count >= SAMPLE_CYCLES) begin
            $display("[MUL-ACCEL] Sampling finished.");
            $display("[MUL-ACCEL] sample cycles        = %0d", cycle_count);
            $display("[MUL-ACCEL] retired instructions= %0d", instret_count);
            $display("[MUL-ACCEL] helper decode hits  = %0d", helper_hit_count);
            $display("[MUL-ACCEL] helper executes     = %0d", helper_exec_count);
            $display("[MUL-ACCEL] x10 write count     = %0d", x10_write_count);
            $display("[MUL-ACCEL] pc redirects        = %0d", pc_redirect_count);
            $display("[MUL-ACCEL] time at 200 MHz     = %0f ns",
                     cycle_count * CPU_CLK_PERIOD_NS);

            if (helper_hit_count == 0) begin
                $display("[MUL-ACCEL] FAIL: helper decode condition was never satisfied.");
            end else if (helper_exec_count == 0) begin
                $display("[MUL-ACCEL] FAIL: helper was detected in ID, but never entered EX.");
            end else begin
                $display("[MUL-ACCEL] FAIL: helper executed, but helper writeback x10=63 was not observed.");
            end

            $finish;
        end
    end

endmodule