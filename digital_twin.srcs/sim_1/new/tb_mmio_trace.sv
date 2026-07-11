`timescale 1ns / 1ps

module tb_mmio_trace;
    localparam [31:0] SEG_ADDR = 32'h8020_0020;
    localparam [31:0] LED_ADDR = 32'h8020_0040;
    localparam [31:0] CNT_ADDR = 32'h8020_0050;

    reg cpu_clk = 1'b0;
    reg clk_50m = 1'b0;
    reg rst = 1'b1;
    reg [7:0] virtual_key = 8'h00;
    reg [63:0] virtual_sw = 64'h0;

    wire [31:0] virtual_led;
    wire [39:0] virtual_seg;

    integer cpu_cycles = 0;
    integer mmio_writes = 0;
    integer led_writes = 0;
    integer seg_writes = 0;
    integer cnt_writes = 0;
    integer done_countdown = -1;

    student_top dut (
        .w_cpu_clk   (cpu_clk),
        .w_clk_50Mhz (clk_50m),
        .w_clk_rst   (rst),
        .virtual_key (virtual_key),
        .virtual_sw  (virtual_sw),
        .virtual_led (virtual_led),
        .virtual_seg (virtual_seg)
    );

    always #3.333 cpu_clk = ~cpu_clk; // 150 MHz
    always #10 clk_50m = ~clk_50m;    // 50 MHz

    initial begin
        $display("[MMIO_TRACE] start");
        #200;
        rst = 1'b0;
        $display("[MMIO_TRACE] reset_release t=%0.1f ns", $realtime);
        #100000000;
        $display("[MMIO_TRACE][TIMEOUT] t=%0.1f ns cycles=%0d writes=%0d led=%0d seg=%0d cnt=%0d pc=%h instr=%h led_out=%h seg_out=%h",
            $realtime, cpu_cycles, mmio_writes, led_writes, seg_writes, cnt_writes,
            dut.Core_cpu.pc_q, dut.instruction, virtual_led, virtual_seg);
        $finish;
    end

    always @(posedge cpu_clk) begin
        if (rst) begin
            cpu_cycles <= 0;
        end else begin
            cpu_cycles <= cpu_cycles + 1;

            if (dut.perip_wen &&
                (dut.perip_addr == SEG_ADDR ||
                 dut.perip_addr == LED_ADDR ||
                 dut.perip_addr == CNT_ADDR)) begin
                mmio_writes <= mmio_writes + 1;
                if (dut.perip_addr == LED_ADDR) led_writes <= led_writes + 1;
                if (dut.perip_addr == SEG_ADDR) seg_writes <= seg_writes + 1;
                if (dut.perip_addr == CNT_ADDR) cnt_writes <= cnt_writes + 1;
                $display("[MMIO_WRITE] t=%0.1f ns cycle=%0d pc=%h instr=%h addr=%h wdata=%h ifid_instr=%h idex_instr=%h exmem_pc=%h exmem_addr=%h exmem_we=%0d",
                    $realtime,
                    cpu_cycles,
                    dut.Core_cpu.pc_q,
                    dut.instruction,
                    dut.perip_addr,
                    dut.perip_wdata,
                    dut.Core_cpu.ifid_instr,
                    dut.Core_cpu.idex_instr,
                    dut.Core_cpu.exmem_pc,
                    dut.Core_cpu.exmem_alu_y,
                    dut.Core_cpu.exmem_mem_write);
            end

            if ((mmio_writes == 0) && ((cpu_cycles % 100000) == 0)) begin
                $display("[PC_TRACE] t=%0.1f ns cycle=%0d pc=%h instr=%h ifid_instr=%h idex_instr=%h exmem_pc=%h exmem_addr=%h exmem_we=%0d load_use=%0d mem_load_stall=%0d m_stall=%0d",
                    $realtime,
                    cpu_cycles,
                    dut.Core_cpu.pc_q,
                    dut.instruction,
                    dut.Core_cpu.ifid_instr,
                    dut.Core_cpu.idex_instr,
                    dut.Core_cpu.exmem_pc,
                    dut.Core_cpu.exmem_alu_y,
                    dut.Core_cpu.exmem_mem_write,
                    dut.Core_cpu.load_use_hazard,
                    dut.Core_cpu.mem_load_stall,
                    dut.Core_cpu.m_stall);
            end

            if ((done_countdown < 0) &&
                (led_writes >= 1) &&
                (seg_writes >= 2) &&
                (cnt_writes >= 2)) begin
                done_countdown <= 1000;
            end else if (done_countdown > 0) begin
                done_countdown <= done_countdown - 1;
            end else if (done_countdown == 0) begin
                $display("[MMIO_TRACE][DONE] t=%0.1f ns cycles=%0d writes=%0d led=%0d seg=%0d cnt=%0d pc=%h instr=%h led_out=%h seg_out=%h",
                    $realtime, cpu_cycles, mmio_writes, led_writes, seg_writes, cnt_writes,
                    dut.Core_cpu.pc_q, dut.instruction, virtual_led, virtual_seg);
                $finish;
            end
        end
    end
endmodule
