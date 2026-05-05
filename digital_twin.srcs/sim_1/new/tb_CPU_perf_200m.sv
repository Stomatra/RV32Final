`timescale 1ns / 1ps

module tb_cpu_perf_200m;

    // CPU 200 MHz，周期 5 ns
    localparam int CPU_CLK_PERIOD_NS = 5;

    // 计数器外设 50 MHz，周期 20 ns
    localparam int CNT_CLK_PERIOD_NS = 20;

    localparam time TIMEOUT_NS = 2_000_000_000;

    logic cpu_clk;
    logic cnt_clk;
    logic rst;

    logic [7:0]  virtual_key;
    logic [63:0] virtual_sw;
    wire  [31:0] virtual_led;
    wire  [39:0] virtual_seg;

    integer cycle_count;
    integer instret_count;
    integer load_use_stall_count;
    integer mem_load_stall_count;
    integer pc_redirect_count;

    student_top uut (
        .w_cpu_clk   (cpu_clk),
        .w_clk_50Mhz (cnt_clk),
        .w_clk_rst   (rst),
        .virtual_key (virtual_key),
        .virtual_sw  (virtual_sw),
        .virtual_led (virtual_led),
        .virtual_seg (virtual_seg)
    );

    // 200 MHz CPU clock
    initial begin
        cpu_clk = 1'b0;
        forever #(CPU_CLK_PERIOD_NS / 2.0) cpu_clk = ~cpu_clk;
    end

    // 50 MHz counter clock
    initial begin
        cnt_clk = 1'b0;
        forever #(CNT_CLK_PERIOD_NS / 2.0) cnt_clk = ~cnt_clk;
    end

    initial begin
        rst = 1'b1;
        virtual_key = 8'h00;
        virtual_sw  = 64'h0;

        repeat (10) @(posedge cpu_clk);
        rst = 1'b0;

        $display("[PERF] Reset released. CPU clock = 200 MHz.");
    end

    // 周期统计
    always_ff @(posedge cpu_clk) begin
        if (rst) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    // 指令退休数量统计
    // 使用 MEM/WB 阶段 valid 信号近似表示一条指令完成执行
    always_ff @(posedge cpu_clk) begin
        if (rst) begin
            instret_count <= 0;
        end else if (uut.Core_cpu.memwb_valid) begin
            instret_count <= instret_count + 1;
        end
    end

    // 统计 load-use 冒险暂停次数
    always_ff @(posedge cpu_clk) begin
        if (rst) begin
            load_use_stall_count <= 0;
        end else if (uut.Core_cpu.load_use_hazard) begin
            load_use_stall_count <= load_use_stall_count + 1;
        end
    end

    // 统计访存读等待暂停次数
    always_ff @(posedge cpu_clk) begin
        if (rst) begin
            mem_load_stall_count <= 0;
        end else if (uut.Core_cpu.mem_load_stall) begin
            mem_load_stall_count <= mem_load_stall_count + 1;
        end
    end

    // 统计分支/跳转导致的 PC 重定向次数
    always_ff @(posedge cpu_clk) begin
        if (rst) begin
            pc_redirect_count <= 0;
        end else if (uut.Core_cpu.ex_pc_redirect) begin
            pc_redirect_count <= pc_redirect_count + 1;
        end
    end

    // 通过 LED 判断测试程序结束
    localparam int SAMPLE_CYCLES = 2000;

    always_ff @(posedge cpu_clk) begin
        if (!rst && cycle_count >= SAMPLE_CYCLES) begin
            $display("[PERF] Sampling finished.");
            $display("[PERF] sample cycles        = %0d", cycle_count);
            $display("[PERF] retired instructions= %0d", instret_count);
            $display("[PERF] load-use stalls     = %0d", load_use_stall_count);
            $display("[PERF] mem-load stalls     = %0d", mem_load_stall_count);
            $display("[PERF] pc redirects        = %0d", pc_redirect_count);
            $display("[PERF] CPI                 = %f",
                    instret_count == 0 ? 0.0 : cycle_count * 1.0 / instret_count);
            $display("[PERF] time at 200MHz      = %0d ns", cycle_count * 5);
            $finish;
        end
    end

    initial begin
        #TIMEOUT_NS;
        $display("[PERF] TIMEOUT.");
        $display("[PERF] pc=%h led=%h seg=%h",
                 uut.Core_cpu.pc_q, virtual_led, virtual_seg);
        $finish;
    end

endmodule