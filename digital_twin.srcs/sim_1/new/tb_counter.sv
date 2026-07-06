`timescale 1ns / 1ps

module tb_counter;
    // counter 外设单元测试。
    // 通过 start/stop 命令检查跨时钟启停控制和毫秒累加是否正常。

    logic cpu_clk;
    logic cnt_clk;
    logic rst;

    logic [31:0] perip_wdata;
    logic        cnt_wen;
    logic [31:0] perip_rdata;

    localparam START_CMD = 32'h8000_0000;
    localparam STOP_CMD  = 32'hffff_ffff;

    counter dut (
        .cpu_clk     (cpu_clk),
        .cnt_clk     (cnt_clk),
        .rst         (rst),
        .perip_wdata (perip_wdata),
        .cnt_wen     (cnt_wen),
        .perip_rdata (perip_rdata)
    );

    // CPU 时钟，200 MHz
    initial begin
        cpu_clk = 1'b0;
        forever #2.5 cpu_clk = ~cpu_clk;
    end

    // 计数器时钟，50 MHz
    initial begin
        cnt_clk = 1'b0;
        forever #10 cnt_clk = ~cnt_clk;
    end

    task automatic counter_write(input logic [31:0] data);
        begin
            @(negedge cpu_clk);
            perip_wdata = data;
            cnt_wen     = 1'b1;

            @(posedge cpu_clk);
            #1;

            @(negedge cpu_clk);
            cnt_wen     = 1'b0;
            perip_wdata = 32'h0;
        end
    endtask

    initial begin
        rst = 1'b1;
        cnt_wen = 1'b0;
        perip_wdata = 32'h0;

        repeat (10) @(posedge cpu_clk);
        rst = 1'b0;

        $display("[CNT] Reset released.");

        // 启动计数器
        counter_write(START_CMD);
        $display("[CNT] Counter start command sent.");

        // 等待超过 2 ms
        #2_200_000;

        if (perip_rdata < 2) begin
            $display("[CNT] FAIL: counter did not increase correctly, cnt_ms=%0d", perip_rdata);
            $finish;
        end

        $display("[CNT] Counter running, cnt_ms=%0d", perip_rdata);

        // 停止计数器
        counter_write(STOP_CMD);
        $display("[CNT] Counter stop command sent.");

        #100_000;

        $display("[CNT] PASS: counter test passed, final cnt_ms=%0d", perip_rdata);
        $finish;
    end

endmodule