`timescale 1ns / 1ps

module tb_rv32i_isa;

    localparam int CLK_PERIOD_NS = 20;
    localparam int TIMEOUT_NS    = 1_200_000_000;

    // 上板/仿真观察到的 RV32I 37 条指令通过显示值：
    // seg = 41d3f4fd3f
    localparam logic [39:0] RV32I_PASS_SEG = 40'h41D3F4FD3F;

    // 防止数码管瞬态误判，要求 PASS 显示连续稳定若干拍
    localparam int PASS_STABLE_CYCLES = 8;

    logic clk;
    logic rst;

    logic [7:0]  virtual_key;
    logic [63:0] virtual_sw;

    wire [31:0] virtual_led;
    wire [39:0] virtual_seg;

    integer cycle_count;
    integer pass_stable_count;

    student_top uut (
        .w_cpu_clk   (clk),
        .w_clk_50Mhz (clk),
        .w_clk_rst   (rst),
        .virtual_key (virtual_key),
        .virtual_sw  (virtual_sw),
        .virtual_led (virtual_led),
        .virtual_seg (virtual_seg)
    );

    // 50 MHz 仿真时钟，周期 20 ns
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    // 复位
    initial begin
        rst = 1'b1;
        virtual_key = 8'h00;
        virtual_sw  = 64'h0;

        repeat (10) @(posedge clk);
        rst = 1'b0;

        $display("[TB] RV32I ISA test reset released.");
    end

    // 周期计数
    always_ff @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    // 识别 RV32I 指令测试 PASS 输出
    always_ff @(posedge clk) begin
        if (rst) begin
            pass_stable_count <= 0;
        end else begin
            if (virtual_seg === RV32I_PASS_SEG) begin
                pass_stable_count <= pass_stable_count + 1;

                if (pass_stable_count >= PASS_STABLE_CYCLES - 1) begin
                    $display("[TB] PASS: RV32I ISA test finished.");
                    $display("[TB] cycles = %0d", cycle_count);
                    $display("[TB] pc     = %h", uut.Core_cpu.pc_q);
                    $display("[TB] led    = %h", virtual_led);
                    $display("[TB] seg    = %h", virtual_seg);
                    $finish;
                end
            end else begin
                pass_stable_count <= 0;
            end
        end
    end

    // 超时兜底
    initial begin
        #TIMEOUT_NS;

        $display("[TB] TIMEOUT: RV32I ISA test did not finish.");
        $display("[TB] pc     = %h", uut.Core_cpu.pc_q);
        $display("[TB] led    = %h", virtual_led);
        $display("[TB] seg    = %h", virtual_seg);
        $display("[TB] cycles = %0d", cycle_count);

        $finish;
    end

endmodule