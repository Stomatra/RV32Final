`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/16/2025 06:21:13 PM
// Design Name: 
// Module Name: student_top
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

`ifdef DEBUG_HW_MILESTONE
`define STUDENT_TOP_DEBUG_MMIO
`endif
`ifdef DEBUG_OBSERVE_MMIO
`define STUDENT_TOP_DEBUG_MMIO
`endif


module student_top#(
    parameter                           P_SW_CNT            = 64,
    parameter                           P_LED_CNT           = 32,
    parameter                           P_SEG_CNT           = 40,
    parameter                           P_KEY_CNT           = 8
) (
    input                                       w_cpu_clk     ,
    input                                       w_clk_50Mhz   ,
    input                                       w_clk_rst     ,
    input  [P_KEY_CNT - 1:0]                    virtual_key   ,
    input  [P_SW_CNT  - 1:0]                    virtual_sw    ,

    output [P_LED_CNT - 1:0]                    virtual_led   ,
    output [P_SEG_CNT - 1:0]                    virtual_seg   
);
	// student_top 是“CPU 子系统”顶层：
	// - 连接 CPU / IROM / 外设桥
	// - 不处理跨时钟同步，那部分留给更外层 top
	// - w_cpu_clk 跑 CPU，w_clk_50Mhz 提供给计数器等慢速外设

    // IROM
    logic [11:0] inst_addr;
    logic        inst_en;
    logic [31:0] instruction;

    // perip
    logic [31:0] perip_addr, perip_wdata, perip_rdata;
    logic perip_wen;
    logic [1:0] perip_mask;
    logic [3:0] perip_wstrb;
    logic [31:0] bridge_virtual_led;
    logic [39:0] bridge_virtual_seg;

`ifdef DEBUG_BRIDGE_CYCLE
    localparam logic [28:0] BRIDGE_DEBUG_PAGE_LAST = 29'd499_999_999;

    logic [31:0] bridge_dbg_seg_wdata;
    logic [31:0] bridge_dbg_led_value;
    logic [31:0] bridge_dbg_last_bridge_addr;
    logic [31:0] bridge_dbg_last_bridge_wdata;
    logic [31:0] bridge_dbg_last_seg_wdata;
    logic [31:0] bridge_dbg_last_led_wdata;
    logic [31:0] bridge_dbg_seen_flags;

    logic [31:0] bridge_dbg_seg_wdata_50_1, bridge_dbg_seg_wdata_50_2;
    logic [31:0] bridge_dbg_led_value_50_1, bridge_dbg_led_value_50_2;
    logic [31:0] bridge_dbg_last_bridge_addr_50_1, bridge_dbg_last_bridge_addr_50_2;
    logic [31:0] bridge_dbg_last_bridge_wdata_50_1, bridge_dbg_last_bridge_wdata_50_2;
    logic [31:0] bridge_dbg_last_seg_wdata_50_1, bridge_dbg_last_seg_wdata_50_2;
    logic [31:0] bridge_dbg_last_led_wdata_50_1, bridge_dbg_last_led_wdata_50_2;
    logic [31:0] bridge_dbg_seen_flags_50_1, bridge_dbg_seen_flags_50_2;

    logic [28:0] bridge_debug_page_counter;
    logic [2:0]  bridge_debug_page;
    logic [31:0] bridge_debug_display_word;
    logic [39:0] bridge_debug_seg_output;
    logic [6:0]  bridge_debug_seg1;
    logic [6:0]  bridge_debug_seg2;
    logic [6:0]  bridge_debug_seg3;
    logic [6:0]  bridge_debug_seg4;
    logic [7:0]  bridge_debug_ans;
`endif

`ifdef STUDENT_TOP_DEBUG_MMIO
    localparam logic [31:0] RESET_PC = 32'h8000_0000;
    localparam logic [31:0] DBG_PC_SEG1 = 32'h8000_0140;
    localparam logic [31:0] DBG_PC_SEG2 = 32'h8000_01A4;
    localparam logic [31:0] DBG_PC_LED  = 32'h8000_01DC;
    localparam logic [31:0] DBG_PC_CNT_START = 32'h8000_02E8;
    localparam logic [31:0] DBG_PC_CNT_STOP  = 32'h8000_031C;
    localparam logic [31:0] SEG_ADDR = 32'h8020_0020;
    localparam logic [31:0] LED_ADDR = 32'h8020_0040;
    localparam logic [31:0] CNT_ADDR = 32'h8020_0050;
    localparam logic [23:0] STUCK_PC_CYCLES = 24'd1_000_000;

    logic [31:0] debug_pc_q;
    logic        debug_load_use_hazard;
    logic        debug_pc_ex1_hazard;
    logic        debug_pc_mem_hazard;
    logic        debug_mem_load_stall;
    logic        debug_m_stall;
    logic        debug_ex_pc_redirect;
    logic [31:0] debug_perip_pc;

    logic [31:0] debug_sticky;
    logic [31:0] last_pc;
    logic [31:0] last_mmio_pc;
    logic [31:0] last_mmio_addr;
    logic [31:0] last_mmio_wdata;
    logic [31:0] last_seg_wdata;
    logic [31:0] last_led_wdata;
    logic [31:0] last_cnt_wdata;
    logic [23:0] same_pc_count;
    logic [31:0] debug_display_word;
    logic [31:0] debug_stall_flags;
    logic [39:0] debug_seg_output;
    logic [6:0]  debug_seg1;
    logic [6:0]  debug_seg2;
    logic [6:0]  debug_seg3;
    logic [6:0]  debug_seg4;
    logic [7:0]  debug_ans;
`endif

	// 核心 CPU 实例。
    myCPU Core_cpu (
        .cpu_rst            (w_clk_rst),
        .cpu_clk            (w_cpu_clk),

        // Interface to IROM
		.irom_addr          (inst_addr),
		.irom_en            (inst_en),
		.irom_data          (instruction),   

        // Interface to DRAM & periphera
        .perip_addr         (perip_addr),     
        .perip_wen          (perip_wen),     
        .perip_mask         (perip_mask),   
        .perip_wstrb        (perip_wstrb),
        .perip_wdata        (perip_wdata),    
        .perip_rdata        (perip_rdata)
`ifdef STUDENT_TOP_DEBUG_MMIO
        ,
        .dbg_pc_q           (debug_pc_q),
        .dbg_load_use_hazard(debug_load_use_hazard),
        .dbg_pc_ex1_hazard   (debug_pc_ex1_hazard),
        .dbg_pc_mem_hazard  (debug_pc_mem_hazard),
        .dbg_mem_load_stall (debug_mem_load_stall),
        .dbg_m_stall        (debug_m_stall),
        .dbg_ex_pc_redirect (debug_ex_pc_redirect),
        .dbg_perip_pc       (debug_perip_pc)
`endif
    );

	// 同步 Block RAM 指令 ROM：CPU 只按字地址取指。
    IROM_BRAM Mem_IROM (
		.clka       (w_cpu_clk),
		.ena        (inst_en),
		.addra      (inst_addr),
		.douta      (instruction)
    );
    
	// 数据访存与 MMIO 统一桥接。
    perip_bridge bridge_inst (
        .clk				(w_cpu_clk),
        .cnt_clk            (w_clk_50Mhz),
        .rst                (w_clk_rst),
        .perip_addr			(perip_addr),
        .perip_wdata		(perip_wdata),
        .perip_wen			(perip_wen),
        .perip_mask			(perip_mask),
        .perip_wstrb			(perip_wstrb),
        .perip_rdata		(perip_rdata),
        .virtual_sw_input	(virtual_sw),
        .virtual_key_input	(virtual_key),	
        .virtual_seg_output	(bridge_virtual_seg),
        .virtual_led_output (bridge_virtual_led)
`ifdef DEBUG_BRIDGE_CYCLE
        ,
        .dbg_seg_wdata          (bridge_dbg_seg_wdata),
        .dbg_led_value          (bridge_dbg_led_value),
        .dbg_last_bridge_addr   (bridge_dbg_last_bridge_addr),
        .dbg_last_bridge_wdata  (bridge_dbg_last_bridge_wdata),
        .dbg_last_seg_wdata     (bridge_dbg_last_seg_wdata),
        .dbg_last_led_wdata     (bridge_dbg_last_led_wdata),
        .dbg_seen_flags         (bridge_dbg_seen_flags)
`endif
    );

`ifdef DEBUG_BRIDGE_CYCLE
    always_ff @(posedge w_clk_50Mhz or posedge w_clk_rst) begin
        if (w_clk_rst) begin
            bridge_dbg_seg_wdata_50_1 <= 32'h0;
            bridge_dbg_seg_wdata_50_2 <= 32'h0;
            bridge_dbg_led_value_50_1 <= 32'h0;
            bridge_dbg_led_value_50_2 <= 32'h0;
            bridge_dbg_last_bridge_addr_50_1 <= 32'h0;
            bridge_dbg_last_bridge_addr_50_2 <= 32'h0;
            bridge_dbg_last_bridge_wdata_50_1 <= 32'h0;
            bridge_dbg_last_bridge_wdata_50_2 <= 32'h0;
            bridge_dbg_last_seg_wdata_50_1 <= 32'h0;
            bridge_dbg_last_seg_wdata_50_2 <= 32'h0;
            bridge_dbg_last_led_wdata_50_1 <= 32'h0;
            bridge_dbg_last_led_wdata_50_2 <= 32'h0;
            bridge_dbg_seen_flags_50_1 <= 32'h0;
            bridge_dbg_seen_flags_50_2 <= 32'h0;
            bridge_debug_page_counter <= 29'h0;
            bridge_debug_page <= 3'h0;
        end else begin
            bridge_dbg_seg_wdata_50_1 <= bridge_dbg_seg_wdata;
            bridge_dbg_seg_wdata_50_2 <= bridge_dbg_seg_wdata_50_1;
            bridge_dbg_led_value_50_1 <= bridge_dbg_led_value;
            bridge_dbg_led_value_50_2 <= bridge_dbg_led_value_50_1;
            bridge_dbg_last_bridge_addr_50_1 <= bridge_dbg_last_bridge_addr;
            bridge_dbg_last_bridge_addr_50_2 <= bridge_dbg_last_bridge_addr_50_1;
            bridge_dbg_last_bridge_wdata_50_1 <= bridge_dbg_last_bridge_wdata;
            bridge_dbg_last_bridge_wdata_50_2 <= bridge_dbg_last_bridge_wdata_50_1;
            bridge_dbg_last_seg_wdata_50_1 <= bridge_dbg_last_seg_wdata;
            bridge_dbg_last_seg_wdata_50_2 <= bridge_dbg_last_seg_wdata_50_1;
            bridge_dbg_last_led_wdata_50_1 <= bridge_dbg_last_led_wdata;
            bridge_dbg_last_led_wdata_50_2 <= bridge_dbg_last_led_wdata_50_1;
            bridge_dbg_seen_flags_50_1 <= bridge_dbg_seen_flags;
            bridge_dbg_seen_flags_50_2 <= bridge_dbg_seen_flags_50_1;

            if (bridge_debug_page_counter == BRIDGE_DEBUG_PAGE_LAST) begin
                bridge_debug_page_counter <= 29'h0;
                bridge_debug_page <= bridge_debug_page + 3'd1;
            end else begin
                bridge_debug_page_counter <= bridge_debug_page_counter + 29'd1;
            end
        end
    end

    always_comb begin
        unique case (bridge_debug_page)
            3'd0: bridge_debug_display_word = 32'hD000_0000;
            3'd1: bridge_debug_display_word = bridge_dbg_seg_wdata_50_2;
            3'd2: bridge_debug_display_word = bridge_dbg_led_value_50_2;
            3'd3: bridge_debug_display_word = bridge_dbg_last_bridge_addr_50_2;
            3'd4: bridge_debug_display_word = bridge_dbg_last_bridge_wdata_50_2;
            3'd5: bridge_debug_display_word = bridge_dbg_last_seg_wdata_50_2;
            3'd6: bridge_debug_display_word = bridge_dbg_last_led_wdata_50_2;
            default: bridge_debug_display_word = bridge_dbg_seen_flags_50_2;
        endcase
    end

    display_seg bridge_debug_seg_driver (
        .clk    (w_clk_50Mhz),
        .rst    (w_clk_rst),
        .s      (bridge_debug_display_word),
        .seg1   (bridge_debug_seg1),
        .seg2   (bridge_debug_seg2),
        .seg3   (bridge_debug_seg3),
        .seg4   (bridge_debug_seg4),
        .ans    (bridge_debug_ans)
    );

    assign bridge_debug_seg_output = {
        bridge_debug_ans[7:6], 1'b0, bridge_debug_seg4,
        bridge_debug_ans[5:4], 1'b0, bridge_debug_seg3,
        bridge_debug_ans[3:2], 1'b0, bridge_debug_seg2,
        bridge_debug_ans[1:0], 1'b0, bridge_debug_seg1
    };
`endif

`ifdef STUDENT_TOP_DEBUG_MMIO
    always_ff @(posedge w_cpu_clk or posedge w_clk_rst) begin
        if (w_clk_rst) begin
            debug_sticky <= 32'h0;
            last_pc <= RESET_PC;
            last_mmio_pc <= 32'h0;
            last_mmio_addr <= 32'h0;
            last_mmio_wdata <= 32'h0;
            last_seg_wdata <= 32'h0;
            last_led_wdata <= 32'h0;
            last_cnt_wdata <= 32'h0;
            same_pc_count <= 24'h0;
        end else begin
            debug_sticky[0]  <= 1'b1;
            debug_sticky[1]  <= debug_sticky[1]  | (debug_pc_q == RESET_PC);
            debug_sticky[2]  <= debug_sticky[2]  | (debug_pc_q != RESET_PC);
            debug_sticky[3]  <= debug_sticky[3]  | (debug_pc_q == DBG_PC_SEG1);
            debug_sticky[4]  <= debug_sticky[4]  | (debug_pc_q == DBG_PC_LED);
            debug_sticky[5]  <= debug_sticky[5]  | perip_wen;
            debug_sticky[6]  <= debug_sticky[6]  | (perip_wen && (perip_addr == SEG_ADDR));
            debug_sticky[7]  <= debug_sticky[7]  | (perip_wen && (perip_addr == LED_ADDR));
            debug_sticky[8]  <= debug_sticky[8]  | (perip_wen && (perip_addr == CNT_ADDR));
            debug_sticky[9]  <= debug_sticky[9]  | debug_ex_pc_redirect;
            debug_sticky[10] <= debug_sticky[10] | debug_load_use_hazard;
            debug_sticky[11] <= debug_sticky[11] | debug_pc_ex1_hazard;
            debug_sticky[12] <= debug_sticky[12] | debug_pc_mem_hazard;
            debug_sticky[13] <= debug_sticky[13] | 1'b0;
            debug_sticky[14] <= debug_sticky[14] | debug_mem_load_stall;
            debug_sticky[15] <= debug_sticky[15] | debug_m_stall;
            debug_sticky[20] <= debug_sticky[20] | (debug_pc_q == DBG_PC_SEG2);
            debug_sticky[21] <= debug_sticky[21] | (debug_pc_q == DBG_PC_CNT_START);
            debug_sticky[22] <= debug_sticky[22] | (debug_pc_q == DBG_PC_CNT_STOP);

            if (perip_wen) begin
                last_mmio_pc <= debug_perip_pc;
                last_mmio_addr <= perip_addr;
                last_mmio_wdata <= perip_wdata;
                if (perip_addr == SEG_ADDR) begin
                    last_seg_wdata <= perip_wdata;
                end
                if (perip_addr == LED_ADDR) begin
                    last_led_wdata <= perip_wdata;
                end
                if (perip_addr == CNT_ADDR) begin
                    last_cnt_wdata <= perip_wdata;
                end
            end

            if (debug_pc_q == last_pc) begin
                if (same_pc_count < STUCK_PC_CYCLES) begin
                    same_pc_count <= same_pc_count + 24'd1;
                end else begin
                    debug_sticky[16] <= 1'b1;
                end
            end else begin
                same_pc_count <= 24'h0;
                last_pc <= debug_pc_q;
            end
        end
    end

    assign debug_stall_flags = {
        8'h00,
        debug_sticky[16],
        debug_sticky[15:9],
        8'h00,
        debug_ex_pc_redirect,
        debug_m_stall,
        debug_mem_load_stall,
        1'b0,
        debug_pc_mem_hazard,
        debug_pc_ex1_hazard,
        debug_load_use_hazard,
        perip_wen
    };

    always_comb begin
`ifdef DEBUG_OBSERVE_MMIO
        unique case (virtual_sw[2:0])
            3'b000: debug_display_word = debug_pc_q;
            3'b001: debug_display_word = last_mmio_pc;
            3'b010: debug_display_word = last_mmio_addr;
            3'b011: debug_display_word = last_mmio_wdata;
            3'b100: debug_display_word = last_seg_wdata;
            3'b101: debug_display_word = last_led_wdata;
            3'b110: debug_display_word = last_cnt_wdata;
            default: debug_display_word = debug_stall_flags;
        endcase
`else
        unique case (virtual_sw[1:0])
            2'b00: debug_display_word = debug_pc_q;
            2'b01: debug_display_word = last_mmio_addr;
            2'b10: debug_display_word = last_mmio_wdata;
            default: debug_display_word = debug_stall_flags;
        endcase
`endif
    end

    display_seg debug_seg_driver (
        .clk    (w_clk_50Mhz),
        .rst    (w_clk_rst),
        .s      (debug_display_word),
        .seg1   (debug_seg1),
        .seg2   (debug_seg2),
        .seg3   (debug_seg3),
        .seg4   (debug_seg4),
        .ans    (debug_ans)
    );

    assign debug_seg_output = {
        debug_ans[7:6], 1'b0, debug_seg4,
        debug_ans[5:4], 1'b0, debug_seg3,
        debug_ans[3:2], 1'b0, debug_seg2,
        debug_ans[1:0], 1'b0, debug_seg1
    };

`ifdef DEBUG_HW_MILESTONE
    assign virtual_led = debug_sticky;
    assign virtual_seg = debug_seg_output;
`else
    assign virtual_led = bridge_virtual_led;
    assign virtual_seg = (virtual_sw[2:0] == 3'b000) ? bridge_virtual_seg : debug_seg_output;
`endif
`elsif DEBUG_BRIDGE_CYCLE
    assign virtual_led = bridge_virtual_led;
    assign virtual_seg = bridge_debug_seg_output;
`else
    assign virtual_led = bridge_virtual_led;
    assign virtual_seg = bridge_virtual_seg;
`endif

endmodule

`ifdef STUDENT_TOP_DEBUG_MMIO
`undef STUDENT_TOP_DEBUG_MMIO
`endif
