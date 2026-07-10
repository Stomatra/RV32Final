`timescale 1ns / 1ps

module tb_top;
    localparam integer UART_BIT_NS = 104166;
    localparam integer UART_HALF_BIT_NS = 52083;
    localparam integer UART_FRAME_NS = UART_BIT_NS * 10;
    localparam integer UART_START_TIMEOUT_NS = UART_FRAME_NS * 2;
    localparam integer SNAPSHOT_BYTES = 18;
    localparam integer STARTUP_PROGRESS_CHANGES = 64;
    localparam integer STARTUP_PROGRESS_TIMEOUT = 500000;
    localparam integer POST_LOCK_SETTLE_50M = 8;
    localparam integer POST_CMD_SETTLE_50M = 4;
    localparam integer FINAL_SOAK_CYCLES = 50000;
    localparam integer HEARTBEAT_CYCLES = 200000;
    localparam integer STUCK_WARN_CYCLES = 20000;
    localparam integer STUCK_FATAL_CYCLES = 200000;
    localparam integer SIM_TIMEOUT_NS = 200000000;
    localparam [7:0] OFFICIAL_LED_DONE_MASK = 8'hFF;
    localparam integer LED_GAP_WARN_CYCLES = 500000;
    localparam [31:0] LOOP_PC_START = 32'h8000_0640;
    localparam [31:0] LOOP_PC_END = 32'h8000_0720;
    localparam [31:0] LOOP_BACKEDGE_PC = 32'h8000_06DC;
    localparam [31:0] LOOP_BACKEDGE_TARGET = 32'h8000_0670;
    localparam integer LOOP_BACKEDGE_WATCHDOG = 10000;
    localparam integer ENABLE_LEGACY_CF_EX_TRACE = 0;
    localparam integer ENABLE_LEGACY_M_MODEL_CHECK = 0;
    localparam integer ENABLE_LEGACY_LW_BRANCH_CHECK = 0;
    localparam integer ENABLE_LEGACY_LOOP_BACKEDGE_WATCHDOG = 0;
    localparam integer ENABLE_LEGACY_WB_TRACE = 0;
    localparam integer ENABLE_GAP_INTERVAL_TRACE = 0;
    localparam integer ENABLE_LED_GAP_WARN = 0;
    localparam integer ENABLE_HEARTBEAT_TRACE = 0;

    localparam [1:0] PC_SRC_PC4    = 2'd0;
    localparam [1:0] PC_SRC_BRANCH = 2'd1;
    localparam [1:0] PC_SRC_JAL    = 2'd2;
    localparam [1:0] PC_SRC_JALR   = 2'd3;

    localparam [3:0] M_OP_NONE   = 4'd0;
    localparam [3:0] M_OP_MUL    = 4'd1;
    localparam [3:0] M_OP_MULH   = 4'd2;
    localparam [3:0] M_OP_MULHSU = 4'd3;
    localparam [3:0] M_OP_MULHU  = 4'd4;
    localparam [2:0] CSR_OP_NONE  = 3'd0;

    localparam [31:0] RESET_PC = 32'h8000_0000;
    localparam [31:0] DRAM_ADDR_START = 32'h8010_0000;
    localparam [31:0] DRAM_ADDR_END   = 32'h8013_FFFF;
    localparam [31:0] SW0_ADDR        = 32'h8020_0000;
    localparam [31:0] SW1_ADDR        = 32'h8020_0004;
    localparam [31:0] KEY_ADDR        = 32'h8020_0010;
    localparam [31:0] SEG_ADDR        = 32'h8020_0020;
    localparam [31:0] LED_ADDR        = 32'h8020_0040;
    localparam [31:0] CNT_ADDR        = 32'h8020_0050;

    reg clk;
    reg serial_rx;
    wire serial_tx;

    reg [7:0] snapshot [0:SNAPSHOT_BYTES - 1];
    reg [63:0] expected_sw;
    reg [7:0] expected_key;

    integer idx;
    integer errors;
    integer cpu_cycles;
    integer redirect_cycles;
    integer load_stall_cycles;
    integer m_stall_cycles;
    integer trap_cycles;
    integer illegal_mem_events;
    integer stuck_warns;
    integer same_pc_cycles;
    integer led_write_count;
    integer seg_write_count;
    integer cycles_since_led_write;
    integer loop_backedge_taken_count;

    reg [31:0] last_pc;
    reg [31:0] last_instr;
    reg [31:0] last_led_write;
    reg [31:0] last_seg_write;
    reg [7:0]  max_led_progress;
    reg control_flow_seen;
    reg [31:0] last_x14_wb_pc;
    reg [31:0] last_x14_wb_instr;
    reg [31:0] last_x14_wb_data;
    reg [31:0] last_x15_wb_pc;
    reg [31:0] last_x15_wb_instr;
    reg [31:0] last_x15_wb_data;
    reg [31:0] last_mulhu_rs1;
    reg [31:0] last_mulhu_rs2;
    reg [31:0] last_mulhu_got;
    reg [31:0] last_mulhu_expected;
    reg [31:0] last_mulhu_pc;
    reg        last_mulhu_valid;
    reg [31:0] last_lw_6d8_x15;
    reg        last_lw_6d8_seen;
    reg [31:0] load_addr_6d8;
    reg        load_addr_6d8_seen;
    reg        load_addr_6d8_zero_written;
    reg [7:0]  led_seen_wdata;
    reg        interval_active;
    reg [7:0]  interval_expected_bit;
    reg [31:0] interval_start_pc;
    reg [31:0] interval_end_pc;
    reg [31:0] interval_pc_min;
    reg [31:0] interval_pc_max;
    integer interval_start_cycle;
    integer interval_end_cycle;
    reg interval_hit_expected_bit;
    reg prev_gap_load_use;
    reg prev_gap_mem_load_stall;
    reg prev_gap_m_stall;

    wire [31:0] top_virtual_led;
    wire [39:0] top_virtual_seg;

    wire tb_pll_locked;
    wire tb_cpu_rst;
    wire tb_clk_50mhz;
    wire tb_cpu_clk;
    wire [63:0] tb_virtual_sw;
    wire [7:0] tb_virtual_key;
    wire [31:0] tb_virtual_led;
    wire [39:0] tb_virtual_seg;
    wire [31:0] tb_virtual_led_50;
    wire [39:0] tb_virtual_seg_50;
    wire tb_uart_rx_ready;
    wire [7:0] tb_uart_rx_data;
    wire tb_uart_tx_start;
    wire [7:0] tb_uart_tx_data;
    wire tb_uart_tx_busy;
    wire [11:0] tb_irom_addr;
    wire [31:0] tb_instruction;
    wire [31:0] tb_pc;
    wire tb_ex_redirect;
    wire [31:0] tb_ex_pc_target;
    wire tb_ex_trap_enter;
    wire tb_ex_trap_return;
    wire tb_mem_load_stall;
    wire tb_m_stall;
    wire tb_m_inflight;
    wire tb_m_result_ready;
    wire tb_div_busy;
    wire tb_div_done;
    wire [31:0] tb_perip_addr;
    wire [31:0] tb_perip_wdata;
    wire [31:0] tb_perip_rdata;
    wire tb_perip_wen;
    wire [1:0] tb_perip_mask;
    wire [31:0] tb_csr_mtvec;
    wire [31:0] tb_csr_mepc;
    wire [31:0] tb_csr_mcause;
    wire [31:0] tb_ex_rs1_val;
    wire [31:0] tb_ex_rs2_val;
    wire [4:0] tb_memwb_rd;
    wire [31:0] tb_memwb_wdata;
    wire tb_memwb_rf_we;
    wire [31:0] tb_idex_pc;
    wire [31:0] tb_idex_instr;
    wire [4:0] tb_idex_rs1;
    wire [4:0] tb_idex_rs2;
    wire [1:0] tb_idex_pc_sel;
    wire tb_idex_valid;
    wire [31:0] tb_ex_pc_rs1_val;
    wire [31:0] tb_ex_pc_rs2_val;
    wire tb_ex_br_take;
    wire [3:0] tb_m_op_reg;
    wire [31:0] tb_m_rs1_reg;
    wire [31:0] tb_m_rs2_reg;
    wire [31:0] tb_ex_m_result_reg;
    wire tb_m_start;
    wire [31:0] tb_memwb_pc;
    wire [31:0] tb_exmem_pc;
    wire [31:0] tb_exmem_alu_y;
    wire tb_exmem_valid;
    wire tb_exmem_mem_req;
    wire tb_exmem_mem_write;
    wire tb_load_use_hazard;
    wire [2:0] tb_idex_csr_op;
    wire tb_idex_is_ecall;
    wire tb_idex_is_mret;

    top uut (
        .i_sys_clk_p(clk),
        .i_sys_clk_n(~clk),
        .i_uart_rx(serial_rx),
        .o_uart_tx(serial_tx),
        .virtual_led(top_virtual_led),
        .virtual_seg(top_virtual_seg)
    );

    assign tb_pll_locked      = uut.w_clk_rst;
    assign tb_cpu_rst         = uut.student_top_inst.w_clk_rst;
    assign tb_clk_50mhz       = uut.w_clk_50Mhz;
    assign tb_cpu_clk         = uut.cpu_clk;
    assign tb_virtual_sw      = uut.virtual_sw;
    assign tb_virtual_key     = uut.virtual_key;
    assign tb_virtual_led     = top_virtual_led;
    assign tb_virtual_seg     = top_virtual_seg;
    assign tb_virtual_led_50  = uut.student_virtual_led_50;
    assign tb_virtual_seg_50  = uut.student_virtual_seg_50;
    assign tb_uart_rx_ready   = uut.rx_ready;
    assign tb_uart_rx_data    = uut.rx_data;
    assign tb_uart_tx_start   = uut.tx_start;
    assign tb_uart_tx_data    = uut.tx_data;
    assign tb_uart_tx_busy    = uut.tx_busy;
    assign tb_irom_addr       = uut.student_top_inst.inst_addr;
    assign tb_instruction     = uut.student_top_inst.instruction;
    assign tb_pc              = uut.student_top_inst.Core_cpu.pc_q;
    assign tb_ex_redirect     = uut.student_top_inst.Core_cpu.ex_pc_redirect;
    assign tb_ex_pc_target    = uut.student_top_inst.Core_cpu.ex_pc_target;
    assign tb_ex_trap_enter   = uut.student_top_inst.Core_cpu.ex_trap_enter;
    assign tb_ex_trap_return  = uut.student_top_inst.Core_cpu.ex_trap_return;
    assign tb_mem_load_stall  = uut.student_top_inst.Core_cpu.mem_load_stall;
    assign tb_m_stall         = uut.student_top_inst.Core_cpu.m_stall;
    assign tb_m_inflight      = uut.student_top_inst.Core_cpu.m_inflight;
    assign tb_m_result_ready  = uut.student_top_inst.Core_cpu.m_result_ready;
    assign tb_div_busy        = uut.student_top_inst.Core_cpu.div_busy;
    assign tb_div_done        = uut.student_top_inst.Core_cpu.div_done;
    assign tb_perip_addr      = uut.student_top_inst.perip_addr;
    assign tb_perip_wdata     = uut.student_top_inst.perip_wdata;
    assign tb_perip_rdata     = uut.student_top_inst.perip_rdata;
    assign tb_perip_wen       = uut.student_top_inst.perip_wen;
    assign tb_perip_mask      = uut.student_top_inst.perip_mask;
    assign tb_csr_mtvec       = uut.student_top_inst.Core_cpu.csr_mtvec;
    assign tb_csr_mepc        = uut.student_top_inst.Core_cpu.csr_mepc;
    assign tb_csr_mcause      = uut.student_top_inst.Core_cpu.csr_mcause;
    assign tb_ex_rs1_val      = uut.student_top_inst.Core_cpu.ex_rs1_val;
    assign tb_ex_rs2_val      = uut.student_top_inst.Core_cpu.ex_rs2_val;
    assign tb_memwb_rd        = uut.student_top_inst.Core_cpu.memwb_rd;
    assign tb_memwb_wdata     = uut.student_top_inst.Core_cpu.memwb_wdata;
    assign tb_memwb_rf_we     = uut.student_top_inst.Core_cpu.memwb_rf_we;
    assign tb_idex_pc         = uut.student_top_inst.Core_cpu.idex_pc;
    assign tb_idex_instr      = uut.student_top_inst.Core_cpu.idex_instr;
    assign tb_idex_rs1        = uut.student_top_inst.Core_cpu.idex_rs1;
    assign tb_idex_rs2        = uut.student_top_inst.Core_cpu.idex_rs2;
    assign tb_idex_pc_sel     = uut.student_top_inst.Core_cpu.idex_pc_sel;
    assign tb_idex_valid      = uut.student_top_inst.Core_cpu.idex_valid;
    assign tb_ex_pc_rs1_val   = uut.student_top_inst.Core_cpu.ex_pc_rs1_val;
    assign tb_ex_pc_rs2_val   = uut.student_top_inst.Core_cpu.ex_pc_rs2_val;
    assign tb_ex_br_take      = uut.student_top_inst.Core_cpu.ex_br_take;
    assign tb_m_op_reg        = uut.student_top_inst.Core_cpu.m_op_reg;
    assign tb_m_rs1_reg       = uut.student_top_inst.Core_cpu.m_rs1_reg;
    assign tb_m_rs2_reg       = uut.student_top_inst.Core_cpu.m_rs2_reg;
    assign tb_ex_m_result_reg = uut.student_top_inst.Core_cpu.ex_m_result_reg;
    assign tb_m_start         = uut.student_top_inst.Core_cpu.m_start;
    assign tb_memwb_pc        = uut.student_top_inst.Core_cpu.memwb_pc;
    assign tb_exmem_pc        = uut.student_top_inst.Core_cpu.exmem_pc;
    assign tb_exmem_alu_y     = uut.student_top_inst.Core_cpu.exmem_alu_y;
    assign tb_exmem_valid     = uut.student_top_inst.Core_cpu.exmem_valid;
    assign tb_exmem_mem_req   = uut.student_top_inst.Core_cpu.exmem_mem_req;
    assign tb_exmem_mem_write = uut.student_top_inst.Core_cpu.exmem_mem_write;
    assign tb_load_use_hazard = uut.student_top_inst.Core_cpu.load_use_hazard;
    assign tb_idex_csr_op     = uut.student_top_inst.Core_cpu.idex_csr_op;
    assign tb_idex_is_ecall   = uut.student_top_inst.Core_cpu.idex_is_ecall;
    assign tb_idex_is_mret    = uut.student_top_inst.Core_cpu.idex_is_mret;

    function [7:0] next_expected_led_bit;
        input [7:0] seen_bits;
        begin
            next_expected_led_bit = (~seen_bits) & (seen_bits + 8'h01);
        end
    endfunction

    function [31:0] m_mul_expected;
        input [3:0] op;
        input [31:0] rs1;
        input [31:0] rs2;
        reg [63:0] uu_prod;
        reg signed [63:0] ss_prod;
        reg signed [65:0] su_prod;
        begin
            uu_prod = $unsigned(rs1) * $unsigned(rs2);
            ss_prod = $signed(rs1) * $signed(rs2);
            su_prod = $signed({rs1[31], rs1}) * $signed({1'b0, rs2});
            case (op)
                M_OP_MUL:    m_mul_expected = uu_prod[31:0];
                M_OP_MULH:   m_mul_expected = ss_prod[63:32];
                M_OP_MULHSU: m_mul_expected = su_prod[63:32];
                M_OP_MULHU:  m_mul_expected = uu_prod[63:32];
                default:     m_mul_expected = 32'h0;
            endcase
        end
    endfunction

    function integer is_valid_mem_addr;
        input [31:0] addr;
        begin
            is_valid_mem_addr =
                ((addr >= DRAM_ADDR_START) && (addr <= DRAM_ADDR_END)) ||
                (addr == SW0_ADDR) ||
                (addr == SW1_ADDR) ||
                (addr == KEY_ADDR) ||
                (addr == SEG_ADDR) ||
                (addr == LED_ADDR) ||
                (addr == CNT_ADDR);
        end
    endfunction

    task tb_print_summary;
        begin
            $display("[FINAL_MMIO] final_virtual_led=%h", tb_virtual_led_50);
            $display("[FINAL_MMIO] final_virtual_led_7_0=%02h", tb_virtual_led_50[7:0]);
            $display("[FINAL_MMIO] final_virtual_seg=%h", tb_virtual_seg_50);
            $display("[FINAL_MMIO] final_pc=%h", tb_pc);
            $display("[FINAL_MMIO] final_instr=%h", tb_instruction);
        end
    endtask

    task wait_cpu_cycles;
        input integer count;
        integer cycle_idx;
        begin
            for (cycle_idx = 0; cycle_idx < count; cycle_idx = cycle_idx + 1)
                @(posedge tb_cpu_clk);
        end
    endtask

    task wait_50m_cycles;
        input integer count;
        integer cycle_idx;
        begin
            for (cycle_idx = 0; cycle_idx < count; cycle_idx = cycle_idx + 1)
                @(posedge tb_clk_50mhz);
        end
    endtask

    task uart_send_byte;
        input [7:0] data;
        integer bit_idx;
        begin
            serial_rx = 1'b0;
            #(UART_BIT_NS);

            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                serial_rx = data[bit_idx];
                #(UART_BIT_NS);
            end

            serial_rx = 1'b1;
            #(UART_BIT_NS);
        end
    endtask

    task uart_expect_no_tx;
        input integer quiet_ns;
        reg saw_tx;
        begin
            saw_tx = 1'b0;
            fork : uart_quiet_window
                begin
                    wait (serial_tx === 1'b0);
                    saw_tx = 1'b1;
                end
                begin
                    #(quiet_ns);
                end
            join_any
            disable uart_quiet_window;

            if (saw_tx) begin
                errors = errors + 1;
                $display("[TB][FAIL] Unexpected UART TX activity at t=%0.1f ns pc=%h instr=%h", $realtime, tb_pc, tb_instruction);
                tb_print_summary();
                $finish;
            end
        end
    endtask

    task uart_receive_byte;
        output [7:0] data;
        integer bit_idx;
        reg timed_out;
        begin
            data = 8'h00;
            timed_out = 1'b0;

            fork : uart_start_wait
                begin
                    wait (serial_tx === 1'b0);
                end
                begin
                    #(UART_START_TIMEOUT_NS);
                    timed_out = 1'b1;
                end
            join_any
            disable uart_start_wait;

            if (timed_out) begin
                errors = errors + 1;
                $display("[TB][FAIL] UART RX timed out at t=%0.1f ns pc=%h instr=%h", $realtime, tb_pc, tb_instruction);
                tb_print_summary();
                $finish;
            end

            #(UART_HALF_BIT_NS);
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                #(UART_BIT_NS);
                data[bit_idx] = serial_tx;
            end
            #(UART_BIT_NS);
        end
    endtask

    task send_sw_bit;
        input integer one_based_idx;
        input integer value;
        reg [7:0] cmd;
        begin
            cmd = one_based_idx[7:0];
            if (value != 0)
                cmd[7] = 1'b1;
            uart_send_byte(cmd);
            wait_50m_cycles(POST_CMD_SETTLE_50M);
            expected_sw[one_based_idx - 1] = value[0];
        end
    endtask

    task send_key_bit;
        input integer one_based_idx;
        input integer value;
        reg [7:0] cmd;
        begin
            cmd = (8'd64 + one_based_idx[7:0]);
            if (value != 0)
                cmd[7] = 1'b1;
            uart_send_byte(cmd);
            wait_50m_cycles(POST_CMD_SETTLE_50M);
            expected_key[one_based_idx - 1] = value[0];
        end
    endtask

    task request_snapshot;
        integer byte_idx;
        begin
            uart_send_byte(8'h80);
            for (byte_idx = 0; byte_idx < SNAPSHOT_BYTES; byte_idx = byte_idx + 1)
                uart_receive_byte(snapshot[byte_idx]);
        end
    endtask

    task check_snapshot_expected;
        reg [63:0] actual_sw;
        reg [7:0] actual_key;
        reg [31:0] actual_led;
        reg [39:0] actual_seg;
        begin
            actual_seg = {snapshot[4], snapshot[3], snapshot[2], snapshot[1], snapshot[0]};
            actual_key = snapshot[5];
            actual_sw  = {snapshot[13], snapshot[12], snapshot[11], snapshot[10], snapshot[9], snapshot[8], snapshot[7], snapshot[6]};
            actual_led = {snapshot[17], snapshot[16], snapshot[15], snapshot[14]};

            if (tb_virtual_sw !== expected_sw) begin
                errors = errors + 1;
                $display("[TB][FAIL] Internal SW mirror mismatch exp=%h got=%h", expected_sw, tb_virtual_sw);
                tb_print_summary();
                $finish;
            end

            if (tb_virtual_key !== expected_key) begin
                errors = errors + 1;
                $display("[TB][FAIL] Internal KEY mirror mismatch exp=%h got=%h", expected_key, tb_virtual_key);
                tb_print_summary();
                $finish;
            end

            if (actual_sw !== expected_sw) begin
                errors = errors + 1;
                $display("[TB][FAIL] Snapshot SW mismatch exp=%h got=%h", expected_sw, actual_sw);
                tb_print_summary();
                $finish;
            end

            if (actual_key !== expected_key) begin
                errors = errors + 1;
                $display("[TB][FAIL] Snapshot KEY mismatch exp=%h got=%h", expected_key, actual_key);
                tb_print_summary();
                $finish;
            end

            for (idx = 0; idx < SNAPSHOT_BYTES; idx = idx + 1) begin
                if ((^snapshot[idx]) === 1'bx) begin
                    errors = errors + 1;
                    $display("[TB][FAIL] Snapshot byte %0d contains X/Z: %h", idx, snapshot[idx]);
                    tb_print_summary();
                    $finish;
                end
            end

            $display("[TB] Snapshot OK seg=%h key=%h sw=%h led=%h", actual_seg, actual_key, actual_sw, actual_led);
        end
    endtask

    task wait_for_cpu_progress;
        input integer required_changes;
        input integer timeout_cycles;
        integer seen_changes;
        integer seen_cycles;
        reg [31:0] prev_pc;
        begin
            seen_changes = 0;
            seen_cycles = 0;
            prev_pc = tb_pc;

            while ((seen_changes < required_changes) && (seen_cycles < timeout_cycles)) begin
                @(posedge tb_cpu_clk);
                if (!tb_cpu_rst && (tb_pc !== prev_pc))
                    seen_changes = seen_changes + 1;
                prev_pc = tb_pc;
                seen_cycles = seen_cycles + 1;
            end

            if (seen_changes < required_changes) begin
                errors = errors + 1;
                $display("[TB][FAIL] CPU made only %0d/%0d PC changes within %0d cycles", seen_changes, required_changes, timeout_cycles);
                tb_print_summary();
                $finish;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #2.5 clk = ~clk;
    end

    initial begin
        serial_rx = 1'b1;
        expected_sw = 64'h0;
        expected_key = 8'h00;
        errors = 0;
        cpu_cycles = 0;
        redirect_cycles = 0;
        load_stall_cycles = 0;
        m_stall_cycles = 0;
        trap_cycles = 0;
        illegal_mem_events = 0;
        stuck_warns = 0;
        same_pc_cycles = 0;
        led_write_count = 0;
        seg_write_count = 0;
        cycles_since_led_write = 0;
        loop_backedge_taken_count = 0;
        last_pc = RESET_PC;
        last_instr = 32'h0000_0013;
        last_led_write = 32'h0000_0000;
        last_seg_write = 32'h0000_0000;
        max_led_progress = 8'h00;
        control_flow_seen = 1'b0;
        last_x14_wb_pc = 32'h0;
        last_x14_wb_instr = 32'h0;
        last_x14_wb_data = 32'h0;
        last_x15_wb_pc = 32'h0;
        last_x15_wb_instr = 32'h0;
        last_x15_wb_data = 32'h0;
        last_mulhu_rs1 = 32'h0;
        last_mulhu_rs2 = 32'h0;
        last_mulhu_got = 32'h0;
        last_mulhu_expected = 32'h0;
        last_mulhu_pc = 32'h0;
        last_mulhu_valid = 1'b0;
        last_lw_6d8_x15 = 32'h0;
        last_lw_6d8_seen = 1'b0;
        load_addr_6d8 = 32'h0;
        load_addr_6d8_seen = 1'b0;
        load_addr_6d8_zero_written = 1'b0;
        led_seen_wdata = 8'h00;
        interval_active = 1'b0;
        interval_expected_bit = 8'h00;
        interval_start_pc = 32'h0;
        interval_end_pc = 32'h0;
        interval_pc_min = 32'hFFFF_FFFF;
        interval_pc_max = 32'h0000_0000;
        interval_start_cycle = 0;
        interval_end_cycle = 0;
        interval_hit_expected_bit = 1'b0;
        prev_gap_load_use = 1'b0;
        prev_gap_mem_load_stall = 1'b0;
        prev_gap_m_stall = 1'b0;

        for (idx = 0; idx < SNAPSHOT_BYTES; idx = idx + 1)
            snapshot[idx] = 8'h00;
    end

    always @(posedge tb_cpu_clk) begin
        if (tb_cpu_rst) begin
            cpu_cycles <= 0;
            redirect_cycles <= 0;
            load_stall_cycles <= 0;
            m_stall_cycles <= 0;
            trap_cycles <= 0;
            illegal_mem_events <= 0;
            stuck_warns <= 0;
            same_pc_cycles <= 0;
            led_write_count <= 0;
            seg_write_count <= 0;
            cycles_since_led_write <= 0;
            loop_backedge_taken_count <= 0;
            last_pc <= RESET_PC;
            last_instr <= 32'h0000_0013;
            last_led_write <= 32'h0000_0000;
            last_seg_write <= 32'h0000_0000;
            max_led_progress <= 8'h00;
            control_flow_seen <= 1'b0;
            last_x14_wb_pc <= 32'h0;
            last_x14_wb_instr <= 32'h0;
            last_x14_wb_data <= 32'h0;
            last_x15_wb_pc <= 32'h0;
            last_x15_wb_instr <= 32'h0;
            last_x15_wb_data <= 32'h0;
            last_mulhu_rs1 <= 32'h0;
            last_mulhu_rs2 <= 32'h0;
            last_mulhu_got <= 32'h0;
            last_mulhu_expected <= 32'h0;
            last_mulhu_pc <= 32'h0;
            last_mulhu_valid <= 1'b0;
            last_lw_6d8_x15 <= 32'h0;
            last_lw_6d8_seen <= 1'b0;
            load_addr_6d8 <= 32'h0;
            load_addr_6d8_seen <= 1'b0;
            load_addr_6d8_zero_written <= 1'b0;
            led_seen_wdata <= 8'h00;
            interval_active <= 1'b0;
            interval_expected_bit <= 8'h00;
            interval_start_pc <= 32'h0;
            interval_end_pc <= 32'h0;
            interval_pc_min <= 32'hFFFF_FFFF;
            interval_pc_max <= 32'h0000_0000;
            interval_start_cycle <= 0;
            interval_end_cycle <= 0;
            interval_hit_expected_bit <= 1'b0;
            prev_gap_load_use <= 1'b0;
            prev_gap_mem_load_stall <= 1'b0;
            prev_gap_m_stall <= 1'b0;
        end else begin
            cpu_cycles <= cpu_cycles + 1;
            cycles_since_led_write <= cycles_since_led_write + 1;

            if (interval_active) begin
                if (tb_pc < interval_pc_min)
                    interval_pc_min <= tb_pc;
                if (tb_pc > interval_pc_max)
                    interval_pc_max <= tb_pc;

                if ((tb_virtual_led_50[7:0] & interval_expected_bit) != 8'h00) begin
                    interval_active <= 1'b0;
                    interval_hit_expected_bit <= 1'b1;
                    interval_end_pc <= tb_pc;
                    interval_end_cycle <= cpu_cycles;
                end
            end

            // 记录 0x800006d8 的 lw 有效地址
            if (tb_exmem_valid && tb_exmem_mem_req && !tb_exmem_mem_write && (tb_exmem_pc == 32'h8000_06D8)) begin
                load_addr_6d8 <= tb_exmem_alu_y;
                load_addr_6d8_seen <= 1'b1;
            end

            if (tb_ex_redirect)
                redirect_cycles <= redirect_cycles + 1;
            if (tb_mem_load_stall)
                load_stall_cycles <= load_stall_cycles + 1;
            if (tb_m_stall)
                m_stall_cycles <= m_stall_cycles + 1;
            if (tb_ex_trap_enter || tb_ex_trap_return)
                trap_cycles <= trap_cycles + 1;

            max_led_progress <= max_led_progress | tb_virtual_led_50[7:0];

            if (tb_perip_wen && (tb_perip_addr == LED_ADDR)) begin
                led_write_count <= led_write_count + 1;
                last_led_write <= tb_perip_wdata;
                cycles_since_led_write <= 0;
                $display("[TB][LED WRITE] t=%0.1f ns pc=%h wdata=%h",
                    $realtime, tb_pc, tb_perip_wdata);

                if ((tb_perip_wdata[7:0] & ~led_seen_wdata) != 8'h00) begin
                    led_seen_wdata <= led_seen_wdata | tb_perip_wdata[7:0];
                    interval_expected_bit <= next_expected_led_bit(led_seen_wdata | tb_perip_wdata[7:0]);
                    interval_active <= (next_expected_led_bit(led_seen_wdata | tb_perip_wdata[7:0]) != 8'h00);
                    interval_hit_expected_bit <= 1'b0;
                    interval_start_pc <= tb_pc;
                    interval_end_pc <= 32'h0;
                    interval_start_cycle <= cpu_cycles;
                    interval_end_cycle <= 0;
                    interval_pc_min <= tb_pc;
                    interval_pc_max <= tb_pc;
                end
            end

            if (tb_perip_wen && (tb_perip_addr == SEG_ADDR)) begin
                seg_write_count <= seg_write_count + 1;
                last_seg_write <= tb_perip_wdata;
                $display("[TB][SEG WRITE] t=%0.1f ns pc=%h wdata=%h",
                    $realtime, tb_pc, tb_perip_wdata);
            end

            if (load_addr_6d8_seen && tb_perip_wen && (tb_perip_addr == load_addr_6d8)) begin
                $display("[STORE_TO_LW6D8_ADDR] store_pc=%h addr=%h wdata=%h", tb_exmem_pc, tb_perip_addr, tb_perip_wdata);
                if (tb_perip_wdata == 32'h0000_0000) begin
                    load_addr_6d8_zero_written <= 1'b1;
                end
            end

            if (ENABLE_LED_GAP_WARN && (led_write_count > 0) && (cycles_since_led_write == LED_GAP_WARN_CYCLES)) begin
                $display("[TB][WARN] No new LED write for %0d CPU cycles after first LED update. pc=%h instr=%h led50=%h seg50=%h",
                    LED_GAP_WARN_CYCLES, tb_pc, tb_instruction, tb_virtual_led_50, tb_virtual_seg_50);
            end

            // 旧控制流全量追踪（默认关闭）
            if (ENABLE_LEGACY_CF_EX_TRACE && tb_idex_valid) begin
                if (tb_idex_pc_sel == PC_SRC_BRANCH) begin
                    $display("[TB][CF_EX] BRANCH idex_pc=%h idex_instr=%h idex_rs1=x%0d idex_rs2=x%0d ex_pc_rs1_val=%h ex_pc_rs2_val=%h ex_br_take=%0d ex_pc_redirect=%0d ex_pc_target=%h",
                        tb_idex_pc,
                        tb_idex_instr,
                        tb_idex_rs1,
                        tb_idex_rs2,
                        tb_ex_pc_rs1_val,
                        tb_ex_pc_rs2_val,
                        tb_ex_br_take,
                        tb_ex_redirect,
                        tb_ex_pc_target);
                    control_flow_seen <= 1'b1;
                end else if (tb_idex_pc_sel == PC_SRC_JAL) begin
                    $display("[TB][CF_EX] JAL idex_pc=%h idex_instr=%h idex_rs1=x%0d idex_rs2=x%0d ex_pc_rs1_val=%h ex_pc_rs2_val=%h ex_br_take=%0d ex_pc_redirect=%0d ex_pc_target=%h",
                        tb_idex_pc,
                        tb_idex_instr,
                        tb_idex_rs1,
                        tb_idex_rs2,
                        tb_ex_pc_rs1_val,
                        tb_ex_pc_rs2_val,
                        tb_ex_br_take,
                        tb_ex_redirect,
                        tb_ex_pc_target);
                    control_flow_seen <= 1'b1;
                end else if (tb_idex_pc_sel == PC_SRC_JALR) begin
                    $display("[TB][CF_EX] JALR idex_pc=%h idex_instr=%h idex_rs1=x%0d idex_rs2=x%0d ex_pc_rs1_val=%h ex_pc_rs2_val=%h ex_br_take=%0d ex_pc_redirect=%0d ex_pc_target=%h",
                        tb_idex_pc,
                        tb_idex_instr,
                        tb_idex_rs1,
                        tb_idex_rs2,
                        tb_ex_pc_rs1_val,
                        tb_ex_pc_rs2_val,
                        tb_ex_br_take,
                        tb_ex_redirect,
                        tb_ex_pc_target);
                    control_flow_seen <= 1'b1;
                end
            end

            // 缺失 bit 区间内的定向事件追踪
            if (ENABLE_GAP_INTERVAL_TRACE && interval_active) begin
                if (tb_idex_valid && tb_ex_redirect &&
                    (tb_idex_pc_sel == PC_SRC_BRANCH || tb_idex_pc_sel == PC_SRC_JAL || tb_idex_pc_sel == PC_SRC_JALR)) begin
                    $display("[GAP][REDIR] t=%0.1f ns idex_pc=%h instr=%h redirect=%0d target=%h",
                        $realtime, tb_idex_pc, tb_idex_instr, tb_ex_redirect, tb_ex_pc_target);
                end

                if (tb_idex_valid &&
                    (tb_idex_is_ecall || tb_idex_is_mret || (tb_idex_csr_op != CSR_OP_NONE))) begin
                    $display("[GAP][CSR_TRAP] t=%0.1f ns idex_pc=%h instr=%h csr_op=%0d ecall=%0d mret=%0d",
                        $realtime, tb_idex_pc, tb_idex_instr, tb_idex_csr_op, tb_idex_is_ecall, tb_idex_is_mret);
                end

                if (tb_m_start) begin
                    $display("[GAP][M_START] t=%0.1f ns idex_pc=%h m_op=%0d rs1=%h rs2=%h",
                        $realtime, tb_idex_pc, tb_m_op_reg, tb_m_rs1_reg, tb_m_rs2_reg);
                end

                if (tb_m_result_ready) begin
                    $display("[GAP][M_DONE] t=%0.1f ns idex_pc=%h m_op=%0d result=%h",
                        $realtime, tb_idex_pc, tb_m_op_reg, tb_ex_m_result_reg);
                end

                if ((tb_load_use_hazard != prev_gap_load_use) ||
                    (tb_mem_load_stall != prev_gap_mem_load_stall) ||
                    (tb_m_stall != prev_gap_m_stall)) begin
                    $display("[GAP][STALL] t=%0.1f ns pc=%h instr=%h load_use=%0d mem_load_stall=%0d m_stall=%0d",
                        $realtime, tb_pc, tb_instruction, tb_load_use_hazard, tb_mem_load_stall, tb_m_stall);
                end

                if (tb_exmem_valid && tb_exmem_mem_req && !is_valid_mem_addr(tb_exmem_alu_y)) begin
                    $display("[GAP][ILLEGAL_MEM] t=%0.1f ns exmem_pc=%h addr=%h mem_wr=%0d",
                        $realtime, tb_exmem_pc, tb_exmem_alu_y, tb_exmem_mem_write);
                end

                prev_gap_load_use <= tb_load_use_hazard;
                prev_gap_mem_load_stall <= tb_mem_load_stall;
                prev_gap_m_stall <= tb_m_stall;
            end else begin
                prev_gap_load_use <= 1'b0;
                prev_gap_mem_load_stall <= 1'b0;
                prev_gap_m_stall <= 1'b0;
            end

            // 旧 M 参考模型校验（默认关闭）
            if (ENABLE_LEGACY_M_MODEL_CHECK && tb_m_result_ready &&
                (tb_m_op_reg == M_OP_MUL || tb_m_op_reg == M_OP_MULH ||
                 tb_m_op_reg == M_OP_MULHSU || tb_m_op_reg == M_OP_MULHU)) begin
                if (tb_m_op_reg == M_OP_MULHU) begin
                    last_mulhu_rs1 <= tb_m_rs1_reg;
                    last_mulhu_rs2 <= tb_m_rs2_reg;
                    last_mulhu_got <= tb_ex_m_result_reg;
                    last_mulhu_expected <= m_mul_expected(tb_m_op_reg, tb_m_rs1_reg, tb_m_rs2_reg);
                    last_mulhu_pc <= tb_idex_pc;
                    last_mulhu_valid <= 1'b1;
                end

                if (tb_ex_m_result_reg !== m_mul_expected(tb_m_op_reg, tb_m_rs1_reg, tb_m_rs2_reg)) begin
                    $display("[TB][FAIL][M_MODEL] op=%0d rs1=%h rs2=%h got=%h expected=%h idex_pc=%h",
                        tb_m_op_reg,
                        tb_m_rs1_reg,
                        tb_m_rs2_reg,
                        tb_ex_m_result_reg,
                        m_mul_expected(tb_m_op_reg, tb_m_rs1_reg, tb_m_rs2_reg),
                        tb_idex_pc);
                    $fatal;
                end
            end

            // 旧 lw/branch hazard 检查（默认关闭）
            if (ENABLE_LEGACY_LW_BRANCH_CHECK && (tb_memwb_pc == 32'h8000_06D8) && tb_memwb_rf_we && (tb_memwb_rd == 5'd15)) begin
                last_lw_6d8_x15 <= tb_memwb_wdata;
                last_lw_6d8_seen <= 1'b1;
                $display("[LW6D8_WB] wdata=%h memwb_pc=%h memwb_rd=%0d", tb_memwb_wdata, tb_memwb_pc, tb_memwb_rd);

                if (load_addr_6d8_zero_written && (tb_memwb_wdata != 32'h0000_0000)) begin
                    $display("[FAIL][LOAD_MEM_MISMATCH] lw@6d8 read non-zero after zero-store: wdata=%h addr=%h", tb_memwb_wdata, load_addr_6d8);
                    $fatal;
                end
            end

            if (ENABLE_LEGACY_LW_BRANCH_CHECK && tb_idex_valid && (tb_idex_pc == 32'h8000_06DC)) begin
                $display("[BR6DC_EX] ex_pc_rs1_val=%h ex_pc_rs2_val=%h ex_br_take=%0d ex_pc_target=%h last_lw_6d8_x15=%h",
                    tb_ex_pc_rs1_val,
                    tb_ex_pc_rs2_val,
                    tb_ex_br_take,
                    tb_ex_pc_target,
                    last_lw_6d8_x15);
                if (last_lw_6d8_seen && (tb_ex_pc_rs1_val != last_lw_6d8_x15)) begin
                    $display("[FAIL][LW_BRANCH_HAZARD] br@6dc rs1=%h last_lw_6d8_x15=%h", tb_ex_pc_rs1_val, last_lw_6d8_x15);
                    $fatal;
                end
            end

            // 旧主循环 WB 追踪（默认关闭）
            if (ENABLE_LEGACY_WB_TRACE && (tb_pc >= LOOP_PC_START) && (tb_pc <= LOOP_PC_END) && tb_memwb_rf_we) begin
                if (tb_memwb_rd == 5'd1 || tb_memwb_rd == 5'd10 || tb_memwb_rd == 5'd11 ||
                    tb_memwb_rd == 5'd13 || tb_memwb_rd == 5'd14 || tb_memwb_rd == 5'd15) begin
                    $display("[TB][WB] pc=%h rd=x%0d wdata=%h instr=%h", tb_pc, tb_memwb_rd, tb_memwb_wdata, tb_instruction);
                end

                if (tb_memwb_rd == 5'd14) begin
                    last_x14_wb_pc <= tb_pc;
                    last_x14_wb_instr <= tb_instruction;
                    last_x14_wb_data <= tb_memwb_wdata;
                end

                if (tb_memwb_rd == 5'd15) begin
                    last_x15_wb_pc <= tb_pc;
                    last_x15_wb_instr <= tb_instruction;
                    last_x15_wb_data <= tb_memwb_wdata;
                end
            end

            // 旧回边 watchdog（默认关闭）
            if (ENABLE_LEGACY_LOOP_BACKEDGE_WATCHDOG && tb_idex_valid &&
                (tb_idex_pc == LOOP_BACKEDGE_PC) &&
                (tb_idex_pc_sel == PC_SRC_BRANCH) &&
                tb_ex_br_take && tb_ex_redirect &&
                (tb_ex_pc_target == LOOP_BACKEDGE_TARGET)) begin
                loop_backedge_taken_count <= loop_backedge_taken_count + 1;
                if (loop_backedge_taken_count + 1 > LOOP_BACKEDGE_WATCHDOG) begin
                    $display("[TB][FAIL][BACKEDGE] loop backedge exceeded %0d takes at idex_pc=%h target=%h",
                        LOOP_BACKEDGE_WATCHDOG, tb_idex_pc, tb_ex_pc_target);
                    $display("[TB][FAIL][BACKEDGE] last x14 wb: pc=%h instr=%h wdata=%h", last_x14_wb_pc, last_x14_wb_instr, last_x14_wb_data);
                    $display("[TB][FAIL][BACKEDGE] last x15 wb: pc=%h instr=%h wdata=%h", last_x15_wb_pc, last_x15_wb_instr, last_x15_wb_data);
                    $display("[TB][FAIL][BACKEDGE] M state: m_start=%0d m_inflight=%0d m_result_ready=%0d m_stall=%0d m_op=%0d m_rs1=%h m_rs2=%h ex_m_result_reg=%h",
                        tb_m_start, tb_m_inflight, tb_m_result_ready, tb_m_stall, tb_m_op_reg, tb_m_rs1_reg, tb_m_rs2_reg, tb_ex_m_result_reg);
                    if (last_mulhu_valid) begin
                        $display("[TB][FAIL][BACKEDGE] last MULHU: idex_pc=%h rs1=%h rs2=%h got=%h expected=%h",
                            last_mulhu_pc, last_mulhu_rs1, last_mulhu_rs2, last_mulhu_got, last_mulhu_expected);
                    end else begin
                        $display("[TB][FAIL][BACKEDGE] last MULHU: none observed yet");
                    end
                    $fatal;
                end
            end

            if (cpu_cycles > POST_LOCK_SETTLE_50M) begin
                if ((^tb_pc) === 1'bx || (^tb_instruction) === 1'bx) begin
                    errors <= errors + 1;
                    $display("[TB][FAIL] X/Z on PC or instruction at t=%0.1f ns pc=%h instr=%h", $realtime, tb_pc, tb_instruction);
                    tb_print_summary();
                    $finish;
                end

                if (tb_pc[31:28] != 4'h8) begin
                    errors <= errors + 1;
                    $display("[TB][FAIL] PC escaped expected 0x8... region at t=%0.1f ns pc=%h instr=%h mtvec=%h mepc=%h mcause=%h",
                        $realtime, tb_pc, tb_instruction, tb_csr_mtvec, tb_csr_mepc, tb_csr_mcause);
                    tb_print_summary();
                    $finish;
                end

                if (tb_pc[1:0] != 2'b00) begin
                    errors <= errors + 1;
                    $display("[TB][FAIL] Misaligned PC at t=%0.1f ns pc=%h target=%h", $realtime, tb_pc, tb_ex_pc_target);
                    tb_print_summary();
                    $finish;
                end

                if (tb_pc == last_pc && !tb_mem_load_stall && !tb_m_stall && !tb_div_busy && !tb_ex_redirect) begin
                    same_pc_cycles <= same_pc_cycles + 1;

                    if (same_pc_cycles == STUCK_WARN_CYCLES) begin
                        stuck_warns <= stuck_warns + 1;
                        $display("[TB][WARN] PC unchanged for %0d cycles at pc=%h instr=%h perip_addr=%h m_inflight=%0d",
                            STUCK_WARN_CYCLES, tb_pc, tb_instruction, tb_perip_addr, tb_m_inflight);
                    end

                    if (same_pc_cycles == STUCK_FATAL_CYCLES) begin
                        errors <= errors + 1;
                        $display("[TB][FAIL] PC stuck for %0d cycles at pc=%h instr=%h mtvec=%h mepc=%h mcause=%h",
                            STUCK_FATAL_CYCLES, tb_pc, tb_instruction, tb_csr_mtvec, tb_csr_mepc, tb_csr_mcause);
                        tb_print_summary();
                        $finish;
                    end
                end else begin
                    same_pc_cycles <= 0;
                end

                if (uut.student_top_inst.Core_cpu.exmem_valid && uut.student_top_inst.Core_cpu.exmem_mem_req &&
                    !is_valid_mem_addr(uut.student_top_inst.Core_cpu.exmem_alu_y)) begin
                    illegal_mem_events <= illegal_mem_events + 1;
                    errors <= errors + 1;
                    $display("[TB][FAIL] Illegal memory access t=%0.1f ns exmem_pc=%h addr=%h mem_wr=%0d funct3=%03b store=%h",
                        $realtime,
                        uut.student_top_inst.Core_cpu.exmem_pc,
                        uut.student_top_inst.Core_cpu.exmem_alu_y,
                        uut.student_top_inst.Core_cpu.exmem_mem_write,
                        uut.student_top_inst.Core_cpu.exmem_funct3,
                        uut.student_top_inst.Core_cpu.exmem_store_data);
                    tb_print_summary();
                    $finish;
                end
            end

            if (ENABLE_HEARTBEAT_TRACE && (cpu_cycles != 0) && ((cpu_cycles % HEARTBEAT_CYCLES) == 0)) begin
                $display("[TB] heartbeat t=%0.1f ns pc=%h instr=%h redir=%0d target=%h stall=%0d mstall=%0d div_busy=%0d perip_addr=%h perip_wen=%0d led50=%h seg50=%h",
                    $realtime,
                    tb_pc,
                    tb_instruction,
                    tb_ex_redirect,
                    tb_ex_pc_target,
                    tb_mem_load_stall,
                    tb_m_stall,
                    tb_div_busy,
                    tb_perip_addr,
                    tb_perip_wen,
                    tb_virtual_led_50,
                    tb_virtual_seg_50);
            end

            last_pc <= tb_pc;
            last_instr <= tb_instruction;
        end
    end

    initial begin : main_test
        wait (tb_pll_locked === 1'b1);
        wait_50m_cycles(POST_LOCK_SETTLE_50M);

        if (tb_cpu_rst !== 1'b0) begin
            errors = errors + 1;
            $display("[TB][FAIL] CPU reset did not deassert after PLL lock");
            tb_print_summary();
            $finish;
        end

        $display("[TB] PLL locked at t=%0.1f ns, starting integrated top-level checks", $realtime);
        wait_for_cpu_progress(STARTUP_PROGRESS_CHANGES, STARTUP_PROGRESS_TIMEOUT);

        uart_expect_no_tx(UART_FRAME_NS);

        $display("[TB] Checking NOP command 0x00 stays silent");
        uart_send_byte(8'h00);
        wait_50m_cycles(POST_CMD_SETTLE_50M);
        uart_expect_no_tx(UART_FRAME_NS);

        if (tb_virtual_sw !== expected_sw || tb_virtual_key !== expected_key) begin
            errors = errors + 1;
            $display("[TB][FAIL] NOP command changed SW/KEY state sw=%h key=%h", tb_virtual_sw, tb_virtual_key);
            tb_print_summary();
            $finish;
        end

        $display("[TB] Checking invalid command 0x49 stays silent");
        uart_send_byte(8'h49);
        wait_50m_cycles(POST_CMD_SETTLE_50M);
        uart_expect_no_tx(UART_FRAME_NS);

        if (tb_virtual_sw !== expected_sw || tb_virtual_key !== expected_key) begin
            errors = errors + 1;
            $display("[TB][FAIL] Invalid command changed SW/KEY state sw=%h key=%h", tb_virtual_sw, tb_virtual_key);
            tb_print_summary();
            $finish;
        end

        $display("[TB] Driving boundary SW/KEY cases through UART");
        send_sw_bit(1, 1);
        send_sw_bit(32, 1);
        send_sw_bit(33, 1);
        send_sw_bit(64, 1);
        send_key_bit(1, 1);
        send_key_bit(8, 1);
        request_snapshot();
        check_snapshot_expected();

        $display("[TB] Driving clear transitions and byte-boundary toggles");
        send_sw_bit(17, 1);
        send_sw_bit(17, 0);
        send_sw_bit(32, 0);
        send_sw_bit(64, 0);
        send_key_bit(1, 0);
        send_key_bit(4, 1);
        request_snapshot();
        check_snapshot_expected();

        $display("[TB] Final soak to catch late runaway/illegal access cases");
        wait_cpu_cycles(FINAL_SOAK_CYCLES);

        if (tb_virtual_led_50[7:0] !== OFFICIAL_LED_DONE_MASK) begin
            errors = errors + 1;
            $display("[TB][FAIL] Official LED progress incomplete: final=%02h expected=%02h max_seen=%02h led_writes=%0d seg_writes=%0d",
                tb_virtual_led_50[7:0], OFFICIAL_LED_DONE_MASK, max_led_progress, led_write_count, seg_write_count);
            $display("[TB][FAIL] Last LED write=%h last SEG write=%h seg50=%h", last_led_write, last_seg_write, tb_virtual_seg_50);
            tb_print_summary();
            $finish;
        end

        if (seg_write_count == 0) begin
            errors = errors + 1;
            $display("[TB][FAIL] No SEG MMIO writes observed during run; seg50=%h", tb_virtual_seg_50);
            tb_print_summary();
            $finish;
        end

        if (errors == 0)
            $display("[TB] PASS: tb_top covered UART protocol, mirror state, and CPU runtime monitors without failures.");
        else
            $display("[TB] FAIL: tb_top completed with %0d errors.", errors);

        tb_print_summary();
        $finish;
    end

    initial begin : sim_timeout
        #SIM_TIMEOUT_NS;
        errors = errors + 1;
        $display("[TB][FAIL] Simulation timeout at t=%0.1f ns", $realtime);
        tb_print_summary();
        $finish;
    end
endmodule

