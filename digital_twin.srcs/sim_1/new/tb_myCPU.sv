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
    // student_top 级综合测试平台。
    // 它把 CPU、外设、计数器和程序运行放在一起，适合跑较长程序、看性能统计与 checkpoint 行为。
    localparam realtime CPU_CLK_HALF_PERIOD = 2.5;
    localparam realtime CNT_CLK_HALF_PERIOD = 10.0;
    localparam time TIMEOUT             = 3s;
    localparam logic [31:0] SEG_ADDR = 32'h8020_0020;
    localparam logic [31:0] LED_ADDR = 32'h8020_0040;
    localparam logic [31:0] CNT_ADDR = 32'h8020_0050;
    localparam logic [31:0] DRAM_ADDR_START = 32'h8010_0000;
    localparam logic [31:0] DRAM_ADDR_END   = 32'h8013_FFFF;
    localparam logic [31:0] MMIO_ADDR_START = 32'h8020_0000;
    localparam logic [31:0] MMIO_ADDR_END   = 32'h8020_00FF;
    localparam logic [31:0] HELPER_ADDR_START = 32'h8000_1fa8;
    localparam logic [31:0] HELPER_ADDR_END   = 32'h8000_1fc8;
    localparam logic [31:0] LOOP004_ADDR_START = 32'h8000_0438;
    localparam logic [31:0] LOOP004_ADDR_END   = 32'h8000_055c;
    localparam logic [31:0] LOOP004_HELPER_RA  = 32'h8000_04c8;
    localparam logic [31:0] LOOP006_ADDR_START = 32'h8000_0690;
    localparam logic [31:0] LOOP006_ADDR_END   = 32'h8000_075c;
    localparam logic [31:0] LOOP006_HELPER_RA  = 32'h8000_0734;
    localparam int LOOP_DIM = 90;
    localparam int LOOP004_TOTAL_ITERS = LOOP_DIM * LOOP_DIM * LOOP_DIM;
    localparam int DRAM_WORD_COUNT = (DRAM_ADDR_END - DRAM_ADDR_START + 32'd1) >> 2;

    logic cpu_clk;
    logic cnt_clk;
    logic rst;
    logic [7:0] virtual_key;
    logic [63:0] virtual_sw;
    wire [31:0] virtual_led;
    wire [39:0] virtual_seg;

    integer cycle_count;
    integer load_stall_cycles;
    integer redirect_cycles;
    integer helper_cycles;
    integer loop004_cycles;
    integer loop006_cycles;
    integer mul_accel_hits;
        integer prev_profile_cycle;
        integer prev_load_stall_cycles;
        integer prev_redirect_cycles;
        integer prev_helper_cycles;
        integer prev_loop004_cycles;
        integer prev_loop006_cycles;
        integer prev_mul_accel_hits;
    bit timer_started;
    bit benchmark_done;
    bit bad_mem_seen;
    bit stale_mem_seen;
    bit loop006_ra_save_seen;
    bit loop006_ra_restore_seen;
    bit loop006_jalr_seen;
    logic [31:0] last_bad_addr;
    logic [31:0] last_bad_pc;
    logic [31:0] last_stale_addr;
    logic [31:0] last_stale_pc;
    string checkpoint_base;
    string checkpoint_restore_base;
    logic [31:0] checkpoint_save_pc;
    bit checkpoint_save_enabled;
    bit checkpoint_restore_enabled;
    bit checkpoint_quit_on_save;
    bit checkpoint_saved;

    student_top uut (
        .w_cpu_clk   (cpu_clk),
        .w_clk_50Mhz (cnt_clk),
        .w_clk_rst   (rst),
        .virtual_key (virtual_key),
        .virtual_sw  (virtual_sw),
        .virtual_led (virtual_led),
        .virtual_seg (virtual_seg)
    );

    function automatic bit tb_is_dram_addr(input logic [31:0] addr);
        tb_is_dram_addr = (addr >= DRAM_ADDR_START) && (addr <= (DRAM_ADDR_END - 32'd3));
    endfunction

    function automatic logic [31:0] tb_read_dram_word(input logic [31:0] addr);
        int word_index;
        begin
            if (!tb_is_dram_addr(addr)) begin
                tb_read_dram_word = 32'hxxxx_xxxx;
            end else begin
                word_index = (addr - DRAM_ADDR_START) >> 2;
                tb_read_dram_word = {
                    uut.bridge_inst.dram_driver_inst.dram_lane3[word_index],
                    uut.bridge_inst.dram_driver_inst.dram_lane2[word_index],
                    uut.bridge_inst.dram_driver_inst.dram_lane1[word_index],
                    uut.bridge_inst.dram_driver_inst.dram_lane0[word_index]
                };
            end
        end
    endfunction

    task automatic tb_ckpt_read_word(
        input integer fd,
        output logic [31:0] value,
        input string field_name
    );
        integer status;
        begin
            status = $fscanf(fd, "%h\n", value);
            if (status != 1) begin
                $display("[TB][CKPT] Failed to read %s from checkpoint", field_name);
                $finish;
            end
        end
    endtask

    task automatic tb_save_dram_lane(input string path, input int lane_sel);
        integer fd;
        integer word_index;
        logic [7:0] lane_byte;
        begin
            fd = $fopen(path, "w");
            if (fd == 0) begin
                $display("[TB][CKPT] Failed to open %s for writing", path);
                $finish;
            end

            for (word_index = 0; word_index < DRAM_WORD_COUNT; word_index = word_index + 1) begin
                case (lane_sel)
                    0: lane_byte = uut.bridge_inst.dram_driver_inst.dram_lane0[word_index];
                    1: lane_byte = uut.bridge_inst.dram_driver_inst.dram_lane1[word_index];
                    2: lane_byte = uut.bridge_inst.dram_driver_inst.dram_lane2[word_index];
                    default: lane_byte = uut.bridge_inst.dram_driver_inst.dram_lane3[word_index];
                endcase
                $fdisplay(fd, "%02x", lane_byte);
            end

            $fclose(fd);
        end
    endtask

    task automatic tb_save_checkpoint(input string base);
        string state_path;
        integer fd;
        integer reg_index;
        begin
            state_path = {base, ".state.hex"};
            fd = $fopen(state_path, "w");
            if (fd == 0) begin
                $display("[TB][CKPT] Failed to open %s for writing", state_path);
                $finish;
            end

            $fdisplay(fd, "%08h", uut.Core_cpu.pc_q);
            $fdisplay(fd, "%08h", uut.Core_cpu.ifid_pc);
            $fdisplay(fd, "%08h", uut.Core_cpu.ifid_instr);
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.ifid_valid});
            $fdisplay(fd, "%08h", uut.Core_cpu.idex_pc);
            $fdisplay(fd, "%08h", {27'h0, uut.Core_cpu.idex_rs1});
            $fdisplay(fd, "%08h", {27'h0, uut.Core_cpu.idex_rs2});
            $fdisplay(fd, "%08h", uut.Core_cpu.idex_rs1_val);
            $fdisplay(fd, "%08h", uut.Core_cpu.idex_rs2_val);
            $fdisplay(fd, "%08h", {27'h0, uut.Core_cpu.idex_rd});
            $fdisplay(fd, "%08h", uut.Core_cpu.idex_imm);
            $fdisplay(fd, "%08h", {29'h0, uut.Core_cpu.idex_funct3});
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.idex_valid});
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.idex_mul_helper});
            $fdisplay(fd, "%08h", uut.Core_cpu.idex_mul_helper_ra);
            $fdisplay(fd, "%08h", uut.Core_cpu.idex_mul_helper_lhs);
            $fdisplay(fd, "%08h", uut.Core_cpu.idex_mul_helper_rhs);
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.idex_rf_we});
            $fdisplay(fd, "%08h", {30'h0, uut.Core_cpu.idex_wb_sel});
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.idex_alu_src_a_sel});
            $fdisplay(fd, "%08h", {30'h0, uut.Core_cpu.idex_alu_src_b_sel});
            $fdisplay(fd, "%08h", {28'h0, uut.Core_cpu.idex_alu_op});
            $fdisplay(fd, "%08h", {30'h0, uut.Core_cpu.idex_pc_sel});
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.idex_mem_req});
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.idex_mem_write});
            $fdisplay(fd, "%08h", {30'h0, uut.Core_cpu.idex_mem_mask});
            $fdisplay(fd, "%08h", uut.Core_cpu.exmem_alu_y);
            $fdisplay(fd, "%08h", uut.Core_cpu.exmem_store_data);
            $fdisplay(fd, "%08h", {27'h0, uut.Core_cpu.exmem_rd});
            $fdisplay(fd, "%08h", {29'h0, uut.Core_cpu.exmem_funct3});
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.exmem_valid});
            $fdisplay(fd, "%08h", uut.Core_cpu.exmem_wb_data);
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.exmem_rf_we});
            $fdisplay(fd, "%08h", {30'h0, uut.Core_cpu.exmem_wb_sel});
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.exmem_mem_req});
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.exmem_mem_write});
            $fdisplay(fd, "%08h", {30'h0, uut.Core_cpu.exmem_mem_mask});
            $fdisplay(fd, "%08h", uut.Core_cpu.exmem_pc);
            $fdisplay(fd, "%08h", uut.Core_cpu.exmem_addr_base);
            $fdisplay(fd, "%08h", uut.Core_cpu.exmem_addr_off);
            $fdisplay(fd, "%08h", uut.Core_cpu.memwb_wdata);
            $fdisplay(fd, "%08h", {27'h0, uut.Core_cpu.memwb_rd});
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.memwb_rf_we});
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.memwb_valid});
            $fdisplay(fd, "%08h", uut.Core_cpu.memwb_pc);
            $fdisplay(fd, "%08h", {31'h0, uut.Core_cpu.mem_stall_flag});
            $fdisplay(fd, "%08h", {31'h0, uut.bridge_inst.counter_inst.start});
            $fdisplay(fd, "%08h", {16'h0, uut.bridge_inst.counter_inst.cnt_1ms});
            $fdisplay(fd, "%08h", uut.bridge_inst.counter_inst.cnt_ms);
            $fdisplay(fd, "%08h", uut.bridge_inst.LED);
            $fdisplay(fd, "%08h", uut.bridge_inst.seg_wdata);
            $fdisplay(fd, "%08h", {31'h0, uut.bridge_inst.sel_dram_r});
            $fdisplay(fd, "%08h", {31'h0, uut.bridge_inst.sel_cnt_r});
            $fdisplay(fd, "%08h", {31'h0, uut.bridge_inst.sel_mmio_r});
            $fdisplay(fd, "%08h", uut.bridge_inst.mmio_rdata_r);
            $fdisplay(fd, "%08h", uut.bridge_inst.cnt_rdata_r);
            $fdisplay(fd, "%08h", uut.bridge_inst.dram_driver_inst.perip_rdata);

            for (reg_index = 0; reg_index < 32; reg_index = reg_index + 1) begin
                $fdisplay(fd, "%08h", uut.Core_cpu.u_rf.reg_bank[reg_index]);
            end

            $fclose(fd);

            tb_save_dram_lane({base, ".dram_lane0.hex"}, 0);
            tb_save_dram_lane({base, ".dram_lane1.hex"}, 1);
            tb_save_dram_lane({base, ".dram_lane2.hex"}, 2);
            tb_save_dram_lane({base, ".dram_lane3.hex"}, 3);

            $display("[TB][CKPT] Saved checkpoint base=%s pc=%h cnt_ms=%0d s0=%h sp=%h",
                base,
                uut.Core_cpu.pc_q,
                uut.bridge_inst.counter_inst.cnt_ms,
                uut.Core_cpu.u_rf.reg_bank[8],
                uut.Core_cpu.u_rf.reg_bank[2]
            );
        end
    endtask

    task automatic tb_restore_checkpoint(input string base);
        string state_path;
        integer fd;
        integer reg_index;
        logic [31:0] tmp_word;
        logic [31:0] cnt_ms_gray_value;
        begin
            state_path = {base, ".state.hex"};
            fd = $fopen(state_path, "r");
            if (fd == 0) begin
                $display("[TB][CKPT] Failed to open %s for reading", state_path);
                $finish;
            end

            tb_ckpt_read_word(fd, tmp_word, "pc_q");
            uut.Core_cpu.pc_q = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "ifid_pc");
            uut.Core_cpu.ifid_pc = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "ifid_instr");
            uut.Core_cpu.ifid_instr = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "ifid_valid");
            uut.Core_cpu.ifid_valid = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "idex_pc");
            uut.Core_cpu.idex_pc = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "idex_rs1");
            uut.Core_cpu.idex_rs1 = tmp_word[4:0];
            tb_ckpt_read_word(fd, tmp_word, "idex_rs2");
            uut.Core_cpu.idex_rs2 = tmp_word[4:0];
            tb_ckpt_read_word(fd, tmp_word, "idex_rs1_val");
            uut.Core_cpu.idex_rs1_val = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "idex_rs2_val");
            uut.Core_cpu.idex_rs2_val = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "idex_rd");
            uut.Core_cpu.idex_rd = tmp_word[4:0];
            tb_ckpt_read_word(fd, tmp_word, "idex_imm");
            uut.Core_cpu.idex_imm = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "idex_funct3");
            uut.Core_cpu.idex_funct3 = tmp_word[2:0];
            tb_ckpt_read_word(fd, tmp_word, "idex_valid");
            uut.Core_cpu.idex_valid = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "idex_mul_helper");
            uut.Core_cpu.idex_mul_helper = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "idex_mul_helper_ra");
            uut.Core_cpu.idex_mul_helper_ra = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "idex_mul_helper_lhs");
            uut.Core_cpu.idex_mul_helper_lhs = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "idex_mul_helper_rhs");
            uut.Core_cpu.idex_mul_helper_rhs = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "idex_rf_we");
            uut.Core_cpu.idex_rf_we = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "idex_wb_sel");
            uut.Core_cpu.idex_wb_sel = tmp_word[1:0];
            tb_ckpt_read_word(fd, tmp_word, "idex_alu_src_a_sel");
            uut.Core_cpu.idex_alu_src_a_sel = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "idex_alu_src_b_sel");
            uut.Core_cpu.idex_alu_src_b_sel = tmp_word[1:0];
            tb_ckpt_read_word(fd, tmp_word, "idex_alu_op");
            uut.Core_cpu.idex_alu_op = tmp_word[3:0];
            tb_ckpt_read_word(fd, tmp_word, "idex_pc_sel");
            uut.Core_cpu.idex_pc_sel = tmp_word[1:0];
            tb_ckpt_read_word(fd, tmp_word, "idex_mem_req");
            uut.Core_cpu.idex_mem_req = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "idex_mem_write");
            uut.Core_cpu.idex_mem_write = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "idex_mem_mask");
            uut.Core_cpu.idex_mem_mask = tmp_word[1:0];
            tb_ckpt_read_word(fd, tmp_word, "exmem_alu_y");
            uut.Core_cpu.exmem_alu_y = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "exmem_store_data");
            uut.Core_cpu.exmem_store_data = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "exmem_rd");
            uut.Core_cpu.exmem_rd = tmp_word[4:0];
            tb_ckpt_read_word(fd, tmp_word, "exmem_funct3");
            uut.Core_cpu.exmem_funct3 = tmp_word[2:0];
            tb_ckpt_read_word(fd, tmp_word, "exmem_valid");
            uut.Core_cpu.exmem_valid = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "exmem_wb_data");
            uut.Core_cpu.exmem_wb_data = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "exmem_rf_we");
            uut.Core_cpu.exmem_rf_we = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "exmem_wb_sel");
            uut.Core_cpu.exmem_wb_sel = tmp_word[1:0];
            tb_ckpt_read_word(fd, tmp_word, "exmem_mem_req");
            uut.Core_cpu.exmem_mem_req = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "exmem_mem_write");
            uut.Core_cpu.exmem_mem_write = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "exmem_mem_mask");
            uut.Core_cpu.exmem_mem_mask = tmp_word[1:0];
            tb_ckpt_read_word(fd, tmp_word, "exmem_pc");
            uut.Core_cpu.exmem_pc = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "exmem_addr_base");
            uut.Core_cpu.exmem_addr_base = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "exmem_addr_off");
            uut.Core_cpu.exmem_addr_off = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "memwb_wdata");
            uut.Core_cpu.memwb_wdata = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "memwb_rd");
            uut.Core_cpu.memwb_rd = tmp_word[4:0];
            tb_ckpt_read_word(fd, tmp_word, "memwb_rf_we");
            uut.Core_cpu.memwb_rf_we = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "memwb_valid");
            uut.Core_cpu.memwb_valid = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "memwb_pc");
            uut.Core_cpu.memwb_pc = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "mem_stall_flag");
            uut.Core_cpu.mem_stall_flag = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "counter.start");
            uut.bridge_inst.counter_inst.start = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "counter.cnt_1ms");
            uut.bridge_inst.counter_inst.cnt_1ms = tmp_word[15:0];
            tb_ckpt_read_word(fd, tmp_word, "counter.cnt_ms");
            uut.bridge_inst.counter_inst.cnt_ms = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "bridge.LED");
            uut.bridge_inst.LED = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "bridge.seg_wdata");
            uut.bridge_inst.seg_wdata = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "bridge.sel_dram_r");
            uut.bridge_inst.sel_dram_r = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "bridge.sel_cnt_r");
            uut.bridge_inst.sel_cnt_r = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "bridge.sel_mmio_r");
            uut.bridge_inst.sel_mmio_r = tmp_word[0];
            tb_ckpt_read_word(fd, tmp_word, "bridge.mmio_rdata_r");
            uut.bridge_inst.mmio_rdata_r = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "bridge.cnt_rdata_r");
            uut.bridge_inst.cnt_rdata_r = tmp_word;
            tb_ckpt_read_word(fd, tmp_word, "dram.perip_rdata");
            uut.bridge_inst.dram_driver_inst.perip_rdata = tmp_word;

            for (reg_index = 0; reg_index < 32; reg_index = reg_index + 1) begin
                tb_ckpt_read_word(fd, tmp_word, $sformatf("reg_bank[%0d]", reg_index));
                uut.Core_cpu.u_rf.reg_bank[reg_index] = tmp_word;
            end

            $fclose(fd);

            $readmemh({base, ".dram_lane0.hex"}, uut.bridge_inst.dram_driver_inst.dram_lane0);
            $readmemh({base, ".dram_lane1.hex"}, uut.bridge_inst.dram_driver_inst.dram_lane1);
            $readmemh({base, ".dram_lane2.hex"}, uut.bridge_inst.dram_driver_inst.dram_lane2);
            $readmemh({base, ".dram_lane3.hex"}, uut.bridge_inst.dram_driver_inst.dram_lane3);

            cnt_ms_gray_value = uut.bridge_inst.counter_inst.cnt_ms ^ (uut.bridge_inst.counter_inst.cnt_ms >> 1);
            uut.bridge_inst.counter_inst.cnt_ms_gray_sync1 = cnt_ms_gray_value;
            uut.bridge_inst.counter_inst.cnt_ms_gray_sync2 = cnt_ms_gray_value;
            uut.bridge_inst.counter_inst.cmd_toggle_cpu = 1'b0;
            uut.bridge_inst.counter_inst.cmd_value_cpu = uut.bridge_inst.counter_inst.start;
            uut.bridge_inst.counter_inst.cmd_toggle_seen = 1'b0;
            uut.bridge_inst.counter_inst.cmd_toggle_sync1 = 1'b0;
            uut.bridge_inst.counter_inst.cmd_toggle_sync2 = 1'b0;
            uut.bridge_inst.counter_inst.cmd_value_sync1 = uut.bridge_inst.counter_inst.start;
            uut.bridge_inst.counter_inst.cmd_value_sync2 = uut.bridge_inst.counter_inst.start;

            cycle_count = 0;
            load_stall_cycles = 0;
            redirect_cycles = 0;
            helper_cycles = 0;
            loop004_cycles = 0;
            loop006_cycles = 0;
            mul_accel_hits = 0;
            prev_profile_cycle = 0;
            prev_load_stall_cycles = 0;
            prev_redirect_cycles = 0;
            prev_helper_cycles = 0;
            prev_loop004_cycles = 0;
            prev_loop006_cycles = 0;
            prev_mul_accel_hits = 0;
            timer_started = uut.bridge_inst.counter_inst.start;
            benchmark_done = 1'b0;
            bad_mem_seen = 1'b0;
            stale_mem_seen = 1'b0;
            loop006_ra_save_seen = 1'b0;
            loop006_ra_restore_seen = 1'b0;
            loop006_jalr_seen = 1'b0;
            last_bad_addr = 32'h0;
            last_bad_pc = 32'h0;
            last_stale_addr = 32'h0;
            last_stale_pc = 32'h0;

            $display("[TB][CKPT] Restored checkpoint base=%s pc=%h cnt_ms=%0d s0=%h sp=%h",
                base,
                uut.Core_cpu.pc_q,
                uut.bridge_inst.counter_inst.cnt_ms,
                uut.Core_cpu.u_rf.reg_bank[8],
                uut.Core_cpu.u_rf.reg_bank[2]
            );
        end
    endtask

    task automatic tb_print_loop004_progress;
        logic [31:0] frame_s0;
        logic [31:0] outer_idx;
        logic [31:0] mid_idx;
        logic [31:0] inner_idx;
        logic [31:0] accum_word;
        integer iter_done;
        integer progress_pct_x10;
        integer est_total_ms;
        integer eta_ms;
        begin
            frame_s0 = uut.Core_cpu.u_rf.reg_bank[8];
            if (!tb_is_dram_addr(frame_s0 - 32'd32) || !tb_is_dram_addr(frame_s0 - 32'd20)) begin
                $display("[TB] Loop004 progress unavailable s0=%h", frame_s0);
            end else begin
                outer_idx = tb_read_dram_word(frame_s0 - 32'd20);
                mid_idx = tb_read_dram_word(frame_s0 - 32'd24);
                inner_idx = tb_read_dram_word(frame_s0 - 32'd28);
                accum_word = tb_read_dram_word(frame_s0 - 32'd32);
                iter_done = (outer_idx * LOOP_DIM * LOOP_DIM) + (mid_idx * LOOP_DIM) + inner_idx;
                if (iter_done < 0) begin
                    iter_done = 0;
                end else if (iter_done > LOOP004_TOTAL_ITERS) begin
                    iter_done = LOOP004_TOTAL_ITERS;
                end
                progress_pct_x10 = (iter_done * 1000) / LOOP004_TOTAL_ITERS;
                if (iter_done > 0) begin
                    est_total_ms = (uut.bridge_inst.counter_inst.cnt_ms * LOOP004_TOTAL_ITERS) / iter_done;
                    eta_ms = est_total_ms - uut.bridge_inst.counter_inst.cnt_ms;
                end else begin
                    est_total_ms = -1;
                    eta_ms = -1;
                end
                $display("[TB] Loop004 progress i=%0d j=%0d k=%0d acc=%h iter=%0d/%0d (%0d.%01d%%) est_total_ms~%0d eta_ms~%0d s0=%h ra=%h",
                    outer_idx,
                    mid_idx,
                    inner_idx,
                    accum_word,
                    iter_done,
                    LOOP004_TOTAL_ITERS,
                    progress_pct_x10 / 10,
                    progress_pct_x10 % 10,
                    est_total_ms,
                    eta_ms,
                    frame_s0,
                    uut.Core_cpu.u_rf.reg_bank[1]
                );
            end
        end
    endtask

    task automatic tb_print_loop006_progress;
        logic [31:0] frame_s0;
        logic [31:0] outer_idx;
        logic [31:0] mid_idx;
        logic [31:0] inner_idx;
        logic [31:0] accum_word;
        integer iter_done;
        integer progress_pct_x10;
        integer est_total_ms;
        integer eta_ms;
        begin
            frame_s0 = uut.Core_cpu.u_rf.reg_bank[8];
            if (!tb_is_dram_addr(frame_s0 - 32'd32) || !tb_is_dram_addr(frame_s0 - 32'd20)) begin
                $display("[TB] Loop006 progress unavailable s0=%h", frame_s0);
            end else begin
                outer_idx = tb_read_dram_word(frame_s0 - 32'd20);
                mid_idx = tb_read_dram_word(frame_s0 - 32'd24);
                inner_idx = tb_read_dram_word(frame_s0 - 32'd28);
                accum_word = tb_read_dram_word(frame_s0 - 32'd32);
                iter_done = (outer_idx * LOOP_DIM * LOOP_DIM) + (mid_idx * LOOP_DIM) + inner_idx;
                if (iter_done < 0) begin
                    iter_done = 0;
                end else if (iter_done > LOOP004_TOTAL_ITERS) begin
                    iter_done = LOOP004_TOTAL_ITERS;
                end
                progress_pct_x10 = (iter_done * 1000) / LOOP004_TOTAL_ITERS;
                if (iter_done > 0) begin
                    est_total_ms = (uut.bridge_inst.counter_inst.cnt_ms * LOOP004_TOTAL_ITERS) / iter_done;
                    eta_ms = est_total_ms - uut.bridge_inst.counter_inst.cnt_ms;
                end else begin
                    est_total_ms = -1;
                    eta_ms = -1;
                end
                $display("[TB] Loop006 progress i=%0d j=%0d k=%0d acc=%h iter=%0d/%0d (%0d.%01d%%) est_total_ms~%0d eta_ms~%0d s0=%h ra=%h",
                    outer_idx,
                    mid_idx,
                    inner_idx,
                    accum_word,
                    iter_done,
                    LOOP004_TOTAL_ITERS,
                    progress_pct_x10 / 10,
                    progress_pct_x10 % 10,
                    est_total_ms,
                    eta_ms,
                    frame_s0,
                    uut.Core_cpu.u_rf.reg_bank[1]
                );
            end
        end
    endtask

    initial begin
        bit explicit_save_requested;
        bit explicit_restore_requested;
        bit explicit_quit_on_save_requested;

        checkpoint_base = "tb_myCPU_ckpt";
        checkpoint_restore_base = "";
        checkpoint_save_pc = 32'h800007e8;
        checkpoint_save_enabled = 1'b0;
        checkpoint_restore_enabled = 1'b0;
        checkpoint_quit_on_save = 1'b0;
        checkpoint_saved = 1'b0;

        if ($value$plusargs("ckpt_base=%s", checkpoint_base)) begin end

        explicit_save_requested = $test$plusargs("ckpt_save");
        if ($value$plusargs("ckpt_save_pc=%h", checkpoint_save_pc)) begin
            explicit_save_requested = 1'b1;
        end

        explicit_restore_requested = 1'b0;
        if ($value$plusargs("ckpt_restore=%s", checkpoint_restore_base)) begin
            explicit_restore_requested = 1'b1;
        end else if ($test$plusargs("ckpt_restore")) begin
            explicit_restore_requested = 1'b1;
            checkpoint_restore_base = checkpoint_base;
        end

        explicit_quit_on_save_requested = $test$plusargs("ckpt_quit_on_save");

        if (explicit_restore_requested) begin
            checkpoint_restore_enabled = 1'b1;
            $display("[TB][CKPT] Explicit restore enabled for base=%s", checkpoint_restore_base);
        end else if (explicit_save_requested) begin
            checkpoint_save_enabled = 1'b1;
            checkpoint_quit_on_save = explicit_quit_on_save_requested;
            $display("[TB][CKPT] Explicit save enabled for base=%s pc=%h quit=%0d",
                checkpoint_base,
                checkpoint_save_pc,
                checkpoint_quit_on_save
            );
        end

        if (checkpoint_save_enabled && explicit_quit_on_save_requested) begin
            checkpoint_quit_on_save = 1'b1;
        end
    end

    initial begin
        cpu_clk = 1'b0;
        forever #CPU_CLK_HALF_PERIOD cpu_clk = ~cpu_clk;
    end

    initial begin
        cnt_clk = 1'b0;
        forever #CNT_CLK_HALF_PERIOD cnt_clk = ~cnt_clk;
    end

    initial begin
        rst = 1'b1;
        virtual_key = '0;
        virtual_sw = '0;

        repeat (10) @(posedge cnt_clk);
        rst = 1'b0;
        if (checkpoint_restore_enabled) begin
            tb_restore_checkpoint(checkpoint_restore_base);
        end
        $display("[TB] Reset released at %0.1f ns", $realtime);
    end

    always @(posedge cpu_clk) begin
        if (!rst && checkpoint_save_enabled && !checkpoint_saved && (uut.Core_cpu.pc_q == checkpoint_save_pc)) begin
            checkpoint_saved = 1'b1;
            tb_save_checkpoint(checkpoint_base);
            if (checkpoint_quit_on_save) begin
                $display("[TB][CKPT] Quit after checkpoint save at t=%0.1f ns", $realtime);
                $finish;
            end
        end
    end

    always_ff @(posedge cpu_clk) begin
        if (rst) begin
            cycle_count <= 0;
            load_stall_cycles <= 0;
            redirect_cycles <= 0;
            helper_cycles <= 0;
            loop004_cycles <= 0;
            loop006_cycles <= 0;
            mul_accel_hits <= 0;
            prev_profile_cycle <= 0;
            prev_load_stall_cycles <= 0;
            prev_redirect_cycles <= 0;
            prev_helper_cycles <= 0;
            prev_loop004_cycles <= 0;
            prev_loop006_cycles <= 0;
            prev_mul_accel_hits <= 0;
        end else begin
            cycle_count <= cycle_count + 1;

            if (uut.Core_cpu.idex_valid && uut.Core_cpu.idex_mul_helper) begin
                mul_accel_hits <= mul_accel_hits + 1;
            end

            if (uut.Core_cpu.mem_load_stall) begin
                load_stall_cycles <= load_stall_cycles + 1;
            end

            if (uut.Core_cpu.ex_pc_redirect) begin
                redirect_cycles <= redirect_cycles + 1;
            end

            if (uut.Core_cpu.pc_q >= 32'h8000_1fa8 && uut.Core_cpu.pc_q <= 32'h8000_1fc8) begin
                helper_cycles <= helper_cycles + 1;
            end

            if (uut.Core_cpu.pc_q >= 32'h8000_044c && uut.Core_cpu.pc_q <= 32'h8000_04f0) begin
                loop004_cycles <= loop004_cycles + 1;
            end

            if (uut.Core_cpu.pc_q >= 32'h8000_06a4 && uut.Core_cpu.pc_q <= 32'h8000_075c) begin
                loop006_cycles <= loop006_cycles + 1;
            end

            // Print a heartbeat every 10ms to avoid staring at waveforms for long runs.
            if ((cycle_count != 0) && ((cycle_count % 2_000_000) == 0)) begin
                $display("[TB] heartbeat t=%0.1f ns pc=%h cnt_ms=%0d seg_raw=%h ex_valid=%0d mem_req=%0d mem_wr=%0d stall=%0d ex_pc=%h ex_addr=%h perip_rdata=%h mem_wb=%h",
                    $realtime,
                    uut.Core_cpu.pc_q,
                    uut.bridge_inst.counter_inst.cnt_ms,
                    uut.bridge_inst.seg_wdata,
                    uut.Core_cpu.exmem_valid,
                    uut.Core_cpu.exmem_mem_req,
                    uut.Core_cpu.exmem_mem_write,
                    uut.Core_cpu.mem_load_stall,
                    uut.Core_cpu.exmem_pc,
                    uut.Core_cpu.exmem_alu_y,
                    uut.Core_cpu.perip_rdata,
                    uut.Core_cpu.mem_wb_data
                );
                    $display("[TB] Profile total cycles=%0d load_stall=%0d redirects=%0d helper_cycles=%0d loop004_cycles=%0d loop006_cycles=%0d mul_accel_hits=%0d",
                        cycle_count,
                        load_stall_cycles,
                        redirect_cycles,
                        helper_cycles,
                        loop004_cycles,
                        loop006_cycles,
                        mul_accel_hits
                    );
                    $display("[TB] Profile delta window_cycles=%0d load_stall=%0d redirects=%0d helper_cycles=%0d loop004_cycles=%0d loop006_cycles=%0d mul_accel_hits=%0d",
                        cycle_count - prev_profile_cycle,
                        load_stall_cycles - prev_load_stall_cycles,
                        redirect_cycles - prev_redirect_cycles,
                        helper_cycles - prev_helper_cycles,
                        loop004_cycles - prev_loop004_cycles,
                        loop006_cycles - prev_loop006_cycles,
                        mul_accel_hits - prev_mul_accel_hits
                    );
                    if (((uut.Core_cpu.pc_q >= LOOP004_ADDR_START) && (uut.Core_cpu.pc_q <= LOOP004_ADDR_END)) ||
                        ((uut.Core_cpu.pc_q >= HELPER_ADDR_START) && (uut.Core_cpu.pc_q <= HELPER_ADDR_END) &&
                         (uut.Core_cpu.u_rf.reg_bank[1] == LOOP004_HELPER_RA))) begin
                        tb_print_loop004_progress();
                    end else if (((uut.Core_cpu.pc_q >= LOOP006_ADDR_START) && (uut.Core_cpu.pc_q <= LOOP006_ADDR_END)) ||
                        ((uut.Core_cpu.pc_q >= HELPER_ADDR_START) && (uut.Core_cpu.pc_q <= HELPER_ADDR_END) &&
                         (uut.Core_cpu.u_rf.reg_bank[1] == LOOP006_HELPER_RA))) begin
                        tb_print_loop006_progress();
                    end
                    prev_profile_cycle <= cycle_count;
                    prev_load_stall_cycles <= load_stall_cycles;
                    prev_redirect_cycles <= redirect_cycles;
                    prev_helper_cycles <= helper_cycles;
                    prev_loop004_cycles <= loop004_cycles;
                    prev_loop006_cycles <= loop006_cycles;
                    prev_mul_accel_hits <= mul_accel_hits;
            end

            if (uut.Core_cpu.perip_wen && (uut.Core_cpu.perip_addr == SEG_ADDR)) begin
                $display("[TB] SEG write t=%0.1f ns pc=%h data=%h", $realtime, uut.Core_cpu.pc_q, uut.Core_cpu.perip_wdata);
            end

            if (uut.Core_cpu.perip_wen && (uut.Core_cpu.perip_addr == LED_ADDR)) begin
                $display("[TB] LED write t=%0.1f ns pc=%h data=%h", $realtime, uut.Core_cpu.pc_q, uut.Core_cpu.perip_wdata);
            end

            if (uut.Core_cpu.perip_wen && (uut.Core_cpu.perip_addr == CNT_ADDR)) begin
                $display("[TB] CNT write t=%0.1f ns pc=%h data=%h", $realtime, uut.Core_cpu.pc_q, uut.Core_cpu.perip_wdata);
            end

            if (!loop006_ra_save_seen && uut.Core_cpu.exmem_valid && uut.Core_cpu.exmem_mem_req && uut.Core_cpu.exmem_mem_write &&
                (uut.Core_cpu.exmem_pc == 32'h8000057c)) begin
                loop006_ra_save_seen <= 1'b1;
                $display("[TB][LOOP006_RA_SAVE] t=%0.1f ns store_pc=%h addr=%h store_data=%h rf_ra=%h sp=%h s0=%h",
                    $realtime,
                    uut.Core_cpu.exmem_pc,
                    uut.Core_cpu.exmem_alu_y,
                    uut.Core_cpu.exmem_store_data,
                    uut.Core_cpu.u_rf.reg_bank[1],
                    uut.Core_cpu.u_rf.reg_bank[2],
                    uut.Core_cpu.u_rf.reg_bank[8]
                );
            end

            if (!loop006_ra_restore_seen && uut.Core_cpu.memwb_valid && uut.Core_cpu.memwb_rf_we && (uut.Core_cpu.memwb_rd == 5'd1) &&
                (uut.Core_cpu.memwb_pc == 32'h800007ec)) begin
                loop006_ra_restore_seen <= 1'b1;
                $display("[TB][LOOP006_RA_RESTORE] t=%0.1f ns load_pc=%h ra_wdata=%h rf_ra=%h exmem_pc=%h exmem_addr=%h sp=%h s0=%h",
                    $realtime,
                    uut.Core_cpu.memwb_pc,
                    uut.Core_cpu.memwb_wdata,
                    uut.Core_cpu.u_rf.reg_bank[1],
                    uut.Core_cpu.exmem_pc,
                    uut.Core_cpu.exmem_alu_y,
                    uut.Core_cpu.u_rf.reg_bank[2],
                    uut.Core_cpu.u_rf.reg_bank[8]
                );
            end

            if (!loop006_jalr_seen && uut.Core_cpu.idex_valid && (uut.Core_cpu.idex_pc == 32'h800007f8)) begin
                loop006_jalr_seen <= 1'b1;
                $display("[TB][LOOP006_JALR] t=%0.1f ns jalr_pc=%h ex_target=%h ex_rs1=%h rf_ra=%h memwb_pc=%h memwb_wdata=%h sp=%h s0=%h",
                    $realtime,
                    uut.Core_cpu.idex_pc,
                    uut.Core_cpu.ex_pc_target,
                    uut.Core_cpu.ex_rs1_val,
                    uut.Core_cpu.u_rf.reg_bank[1],
                    uut.Core_cpu.memwb_pc,
                    uut.Core_cpu.memwb_wdata,
                    uut.Core_cpu.u_rf.reg_bank[2],
                    uut.Core_cpu.u_rf.reg_bank[8]
                );
            end

            if (uut.Core_cpu.memwb_valid && uut.Core_cpu.memwb_rf_we && (uut.Core_cpu.memwb_rd == 5'd8) &&
                (uut.Core_cpu.memwb_wdata < 32'h0001_0000)) begin
                $display("[TB][BAD_S0_WB] t=%0.1f ns memwb_pc=%h s0_wdata=%h sp=%h exmem_pc=%h exmem_addr=%h",
                    $realtime,
                    uut.Core_cpu.memwb_pc,
                    uut.Core_cpu.memwb_wdata,
                    uut.Core_cpu.u_rf.reg_bank[2],
                    uut.Core_cpu.exmem_pc,
                    uut.Core_cpu.exmem_alu_y
                );
            end
        end
    end

    always_ff @(posedge cpu_clk) begin
        if (rst) begin
            timer_started <= 1'b0;
            benchmark_done <= 1'b0;
            bad_mem_seen <= 1'b0;
            stale_mem_seen <= 1'b0;
            loop006_ra_save_seen <= 1'b0;
            loop006_ra_restore_seen <= 1'b0;
            loop006_jalr_seen <= 1'b0;
            last_bad_addr <= 32'h0;
            last_bad_pc <= 32'h0;
            last_stale_addr <= 32'h0;
            last_stale_pc <= 32'h0;
        end else begin
            if (!timer_started && uut.bridge_inst.counter_inst.start) begin
                timer_started <= 1'b1;
                $display("[TB] Timer started at %0.1f ns pc=%h seg_raw=%h seg=%h", $realtime, uut.Core_cpu.pc_q, uut.bridge_inst.seg_wdata, virtual_seg);
            end

            if (timer_started && !benchmark_done && !uut.bridge_inst.counter_inst.start) begin
                benchmark_done <= 1'b1;
                $display("[TB] Benchmark finished at %0.1f ns", $realtime);
                $display("[TB] Summary cycles=%0d pc=%h led=%h seg_raw=%h seg=%h cnt_ms=%0d", cycle_count, uut.Core_cpu.pc_q, virtual_led, uut.bridge_inst.seg_wdata, virtual_seg, uut.bridge_inst.counter_inst.cnt_ms);
                $display("[TB] Profile load_stall=%0d redirects=%0d helper_cycles=%0d loop004_cycles=%0d loop006_cycles=%0d mul_accel_hits=%0d",
                    load_stall_cycles, redirect_cycles, helper_cycles, loop004_cycles, loop006_cycles, mul_accel_hits);
                $finish;
            end

            if (!uut.Core_cpu.exmem_valid && uut.Core_cpu.exmem_mem_req) begin
                if (!stale_mem_seen || (last_stale_addr != uut.Core_cpu.exmem_alu_y) || (last_stale_pc != uut.Core_cpu.exmem_pc)) begin
                    $display("[TB][STALE_MEM] t=%0.1f ns exmem_pc=%h addr=%h mem_wr=%0d base=%h off=%h",
                        $realtime,
                        uut.Core_cpu.exmem_pc,
                        uut.Core_cpu.exmem_alu_y,
                        uut.Core_cpu.exmem_mem_write,
                        uut.Core_cpu.exmem_addr_base,
                        uut.Core_cpu.exmem_addr_off
                    );
                end
                stale_mem_seen <= 1'b1;
                last_stale_addr <= uut.Core_cpu.exmem_alu_y;
                last_stale_pc <= uut.Core_cpu.exmem_pc;
            end else begin
                stale_mem_seen <= 1'b0;
            end

            if (uut.Core_cpu.exmem_valid && uut.Core_cpu.exmem_mem_req &&
                !((uut.Core_cpu.exmem_alu_y >= DRAM_ADDR_START && uut.Core_cpu.exmem_alu_y <= DRAM_ADDR_END) ||
                  (uut.Core_cpu.exmem_alu_y >= MMIO_ADDR_START && uut.Core_cpu.exmem_alu_y <= MMIO_ADDR_END))) begin
                if (!bad_mem_seen || (last_bad_addr != uut.Core_cpu.exmem_alu_y) || (last_bad_pc != uut.Core_cpu.exmem_pc)) begin
                    $display("[TB][BAD_MEM] t=%0.1f ns exmem_pc=%h addr=%h mem_wr=%0d funct3=%03b base=%h off=%h store=%h perip_rdata=%h mem_wb=%h sp=%h s0=%h",
                        $realtime,
                        uut.Core_cpu.exmem_pc,
                        uut.Core_cpu.exmem_alu_y,
                        uut.Core_cpu.exmem_mem_write,
                        uut.Core_cpu.exmem_funct3,
                        uut.Core_cpu.exmem_addr_base,
                        uut.Core_cpu.exmem_addr_off,
                        uut.Core_cpu.exmem_store_data,
                        uut.Core_cpu.perip_rdata,
                        uut.Core_cpu.mem_wb_data,
                        uut.Core_cpu.u_rf.reg_bank[2],
                        uut.Core_cpu.u_rf.reg_bank[8]
                    );
                end
                bad_mem_seen <= 1'b1;
                last_bad_addr <= uut.Core_cpu.exmem_alu_y;
                last_bad_pc <= uut.Core_cpu.exmem_pc;
            end else begin
                bad_mem_seen <= 1'b0;
            end
        end
    end

    initial begin
        #TIMEOUT;
        $display("[TB] Timeout at %0.1f ns", $realtime);
        $display("[TB] Summary cycles=%0d pc=%h led=%h seg_raw=%h seg=%h cnt_ms=%0d timer_started=%0d", cycle_count, uut.Core_cpu.pc_q, virtual_led, uut.bridge_inst.seg_wdata, virtual_seg, uut.bridge_inst.counter_inst.cnt_ms, timer_started);
        $display("[TB] Profile load_stall=%0d redirects=%0d helper_cycles=%0d loop004_cycles=%0d loop006_cycles=%0d mul_accel_hits=%0d",
            load_stall_cycles, redirect_cycles, helper_cycles, loop004_cycles, loop006_cycles, mul_accel_hits);
        $finish;
    end
endmodule
