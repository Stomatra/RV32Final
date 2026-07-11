`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/04/22 10:25:24
// Design Name: 
// Module Name: perip_bridge
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

module perip_bridge(
    input  logic         clk				,
    input  logic         cnt_clk			,
    input  logic         rst                ,

    input  logic [31:0]  perip_addr			,
    input  logic [31:0]  perip_wdata		,
    input  logic         perip_wen			,
	input  logic [1:0]	 perip_mask			,
    output logic [31:0]  perip_rdata		,

	input  logic [63:0]  virtual_sw_input	,
    input  logic [7:0]   virtual_key_input	,	

	output logic [39:0]  virtual_seg_output	,
    output logic [31:0]  virtual_led_output
`ifdef DEBUG_BRIDGE_CYCLE
    ,
    output logic [31:0]  dbg_seg_wdata,
    output logic [31:0]  dbg_led_value,
    output logic [31:0]  dbg_last_bridge_addr,
    output logic [31:0]  dbg_last_bridge_wdata,
    output logic [31:0]  dbg_last_seg_wdata,
    output logic [31:0]  dbg_last_led_wdata,
    output logic [31:0]  dbg_seen_flags
`endif
);
    // perip_bridge 把 CPU 的统一 perip 总线拆成三类目标：
    // 1. DRAM 地址区：转给 dram_driver
    // 2. 计数器地址：转给 counter
    // 3. MMIO 地址：拨码、按键、数码管、LED
    //
    // 这里最关键的时序选择是：
    // - DRAM 读本身是同步 BRAM 返回
    // - MMIO / counter 读也统一打一拍
    // 这样 CPU 只面对“所有读口都是 1 周期返回”的一致模型。
    localparam DRAM_ADDR_START = 32'h8010_0000;
    localparam DRAM_ADDR_END   = 32'h8013_FFFF;
    localparam SW0_ADDR  = 32'h8020_0000;  // sw[31:0]
    localparam SW1_ADDR  = 32'h8020_0004;  // sw[63:32]
    localparam KEY_ADDR  = 32'h8020_0010;  // key[7:0]
    localparam SEG_ADDR  = 32'h8020_0020;  // seg
    localparam LED_ADDR  = 32'h8020_0040;  // led[31:0]
    localparam CNT_ADDR  = 32'h8020_0050;  // counter

    logic [31:0] LED;
    logic [31:0] seg_wdata, cnt_rdata, mmio_rdata, dram_rdata;
    logic [39:0] seg_output;
    logic        sel_sw0;
    logic        sel_sw1;
    logic        sel_key;
    logic        sel_seg;
    logic        sel_led;
    logic        sel_cnt;
    logic        sel_dram;
	// 所有读源统一打一拍，和 dram_driver 的同步读延迟保持一致。
    logic        sel_dram_r, sel_cnt_r, sel_mmio_r;
    logic [31:0] mmio_rdata_r, cnt_rdata_r;
    //添加停一拍的寄存器
    logic [31:0] perip_rdata_next;
    logic [31:0] perip_rdata_q;
`ifdef DEBUG_BRIDGE_CYCLE
    logic [31:0] debug_last_bridge_addr;
    logic [31:0] debug_last_bridge_wdata;
    logic [31:0] debug_last_seg_wdata;
    logic [31:0] debug_last_led_wdata;
    logic [31:0] debug_seen_flags;
`endif

    assign sel_sw0  = (perip_addr == SW0_ADDR);
    assign sel_sw1  = (perip_addr == SW1_ADDR);
    assign sel_key  = (perip_addr == KEY_ADDR);
    assign sel_seg  = (perip_addr == SEG_ADDR);
    assign sel_led  = (perip_addr == LED_ADDR);
    assign sel_cnt  = (perip_addr == CNT_ADDR);
    assign sel_dram = (perip_addr >= DRAM_ADDR_START && perip_addr <= DRAM_ADDR_END);

	// LED / SEG 的写入是最简单的寄存器写；开关与按键是只读输入。
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            LED       <= 32'h0;
            seg_wdata <= 32'h0;
        end else if (perip_wen) begin
            if (sel_led) begin
                LED <= perip_wdata;
            end
            if (sel_seg) begin
                seg_wdata <= perip_wdata;
            end
        end
    end

`ifdef DEBUG_BRIDGE_CYCLE
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            debug_last_bridge_addr <= 32'h0;
            debug_last_bridge_wdata <= 32'h0;
            debug_last_seg_wdata <= 32'h0;
            debug_last_led_wdata <= 32'h0;
            debug_seen_flags <= 32'h0;
        end else if (perip_wen) begin
            debug_last_bridge_addr <= perip_addr;
            debug_last_bridge_wdata <= perip_wdata;
            debug_seen_flags[0] <= 1'b1;
            debug_seen_flags[4] <= debug_seen_flags[4] | (perip_wdata != 32'h0);

            if (sel_seg) begin
                debug_last_seg_wdata <= perip_wdata;
                debug_seen_flags[1] <= 1'b1;
                debug_seen_flags[5] <= debug_seen_flags[5] | (perip_wdata != 32'h0);
            end

            if (sel_led) begin
                debug_last_led_wdata <= perip_wdata;
                debug_seen_flags[2] <= 1'b1;
                debug_seen_flags[6] <= debug_seen_flags[6] | (perip_wdata != 32'h0);
            end

            if (sel_cnt) begin
                debug_seen_flags[3] <= 1'b1;
            end
        end
    end
`endif

	// MMIO 读是组合选择，但结果最终还会被后面的寄存器级统一打一拍。
    always_comb begin
        if (~perip_wen) begin
            if (sel_sw0) begin
                mmio_rdata = virtual_sw_input[31:0];
            end else if (sel_sw1) begin
                mmio_rdata = virtual_sw_input[63:32];
            end else if (sel_key) begin
                mmio_rdata = {24'd0, virtual_key_input};
            end else if (sel_seg) begin
                mmio_rdata = seg_wdata;
            end else begin
                mmio_rdata = 32'hDEAD_BEEF;
            end
        end else begin
            mmio_rdata = 32'h0;
        end
    end

	// display_seg 把 32bit 数值拆成 4 组七段码和位选。
    display_seg seg_driver (
        .clk    (clk),
        .rst    (rst),
        .s      (seg_wdata),
        .seg1   (seg_output[6:0]),
        .seg2   (seg_output[16:10]),
        .seg3   (seg_output[26:20]),
        .seg4   (seg_output[36:30]),
        .ans    ({seg_output[39:38], seg_output[29:28], seg_output[19:18], seg_output[9:8]})
    ); 
   
    assign seg_output[7]  = 0;
    assign seg_output[17] = 0;
    assign seg_output[27] = 0;
    assign seg_output[37] = 0;
    

	// DRAM 地址空间。
    dram_driver dram_driver_inst (
        .clk				(clk),
        .perip_addr			(perip_addr[17:0]),
        .perip_wdata		(perip_wdata),
        .perip_mask			(perip_mask),
        .dram_wen 			(perip_wen & sel_dram),
        .perip_rdata		(dram_rdata)
    );

	// 计数器地址空间。
    counter counter_inst (
		.cpu_clk			(clk),
		.cnt_clk			(cnt_clk),
        .rst                (rst),
        .perip_wdata		(perip_wdata),
        .cnt_wen 			(perip_wen & sel_cnt),
        .perip_rdata		(cnt_rdata)
    );

	// 选择信号和非 BRAM 读数据打一拍，使所有读源都对齐成 1 周期延迟。
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sel_dram_r   <= 1'b0;
            sel_cnt_r    <= 1'b0;
            sel_mmio_r   <= 1'b0;
            mmio_rdata_r <= 32'h0;
            cnt_rdata_r  <= 32'h0;
        end else begin
            sel_dram_r   <= sel_dram;
            sel_cnt_r    <= sel_cnt;
            sel_mmio_r   <= (sel_sw0 || sel_sw1 || sel_key || sel_seg);
            mmio_rdata_r <= mmio_rdata;
            cnt_rdata_r  <= cnt_rdata;
        end
    end

	// CPU 看到的 perip_rdata 在“地址给出后一拍”有效。
    always_comb begin
        if (sel_dram_r) begin
            perip_rdata_next = dram_rdata;    // BRAM output already 1-cycle delayed
        end else if (sel_cnt_r) begin
            perip_rdata_next = cnt_rdata_r;
        end else if (sel_mmio_r) begin
            perip_rdata_next = mmio_rdata_r;
        end else begin
            perip_rdata_next = 32'h0;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            perip_rdata_q <= 32'h0;
        end else begin
            perip_rdata_q <= perip_rdata_next;
        end
    end

    assign perip_rdata = perip_rdata_q;
    
    assign virtual_led_output = LED;
    assign virtual_seg_output = seg_output;

`ifdef DEBUG_BRIDGE_CYCLE
    assign dbg_seg_wdata = seg_wdata;
    assign dbg_led_value = LED;
    assign dbg_last_bridge_addr = debug_last_bridge_addr;
    assign dbg_last_bridge_wdata = debug_last_bridge_wdata;
    assign dbg_last_seg_wdata = debug_last_seg_wdata;
    assign dbg_last_led_wdata = debug_last_led_wdata;
    assign dbg_seen_flags = debug_seen_flags;
`endif

endmodule
