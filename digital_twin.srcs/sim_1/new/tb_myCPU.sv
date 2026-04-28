`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/23/2025 03:50:55 PM
// Design Name: 
// Module Name: tb_myCPU
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_myCPU;
    localparam int CLK_PERIOD_NS = 20;
    localparam int TIMEOUT_NS    = 1_200_000_000;

    logic clk;
    logic rst;
    logic [7:0] virtual_key;
    logic [63:0] virtual_sw;
    wire [31:0] virtual_led;
    wire [39:0] virtual_seg;

    integer cycle_count;
    bit timer_started;
    bit benchmark_done;

    student_top uut (
        .w_cpu_clk   (clk),
        .w_clk_50Mhz (clk),
        .w_clk_rst   (rst),
        .virtual_key (virtual_key),
        .virtual_sw  (virtual_sw),
        .virtual_led (virtual_led),
        .virtual_seg (virtual_seg)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    initial begin
        rst = 1'b1;
        virtual_key = '0;
        virtual_sw = '0;

        repeat (10) @(posedge clk);
        rst = 1'b0;
        $display("[TB] Reset released at %0.1f ns", $realtime);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            timer_started <= 1'b0;
            benchmark_done <= 1'b0;
        end else begin
            if (!timer_started && uut.bridge_inst.counter_inst.start) begin
                timer_started <= 1'b1;
                $display("[TB] Timer started at %0.1f ns pc=%h seg=%h", $realtime, uut.pc, virtual_seg);
            end

            if (timer_started && !benchmark_done && !uut.bridge_inst.counter_inst.start) begin
                benchmark_done <= 1'b1;
                $display("[TB] Benchmark finished at %0.1f ns", $realtime);
                $display("[TB] Summary cycles=%0d pc=%h led=%h seg=%h cnt_ms=%0d", cycle_count, uut.pc, virtual_led, virtual_seg, uut.bridge_inst.counter_inst.cnt_ms);
                $finish;
            end
        end
    end

    initial begin
        #TIMEOUT_NS;
        $display("[TB] Timeout at %0.1f ns", $realtime);
        $display("[TB] Summary cycles=%0d pc=%h led=%h seg=%h cnt_ms=%0d timer_started=%0d", cycle_count, uut.pc, virtual_led, virtual_seg, uut.bridge_inst.counter_inst.cnt_ms, timer_started);
        $finish;
    end
endmodule
