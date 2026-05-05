`timescale 1ns / 1ps

module tb_perip_bridge;

    logic clk;
    logic cnt_clk;
    logic rst;

    logic [31:0] perip_addr;
    logic [31:0] perip_wdata;
    logic        perip_wen;
    logic [1:0]  perip_mask;
    logic [31:0] perip_rdata;

    logic [63:0] virtual_sw_input;
    logic [7:0]  virtual_key_input;
    logic [39:0] virtual_seg_output;
    logic [31:0] virtual_led_output;

    localparam DRAM_BASE = 32'h8010_0000;
    localparam SW0_ADDR  = 32'h8020_0000;
    localparam SW1_ADDR  = 32'h8020_0004;
    localparam KEY_ADDR  = 32'h8020_0010;
    localparam SEG_ADDR  = 32'h8020_0020;
    localparam LED_ADDR  = 32'h8020_0040;

    localparam MASK_BYTE = 2'b00;
    localparam MASK_HALF = 2'b01;
    localparam MASK_WORD = 2'b10;

    perip_bridge dut (
        .clk                (clk),
        .cnt_clk            (cnt_clk),
        .rst                (rst),

        .perip_addr         (perip_addr),
        .perip_wdata        (perip_wdata),
        .perip_wen          (perip_wen),
        .perip_mask         (perip_mask),
        .perip_rdata        (perip_rdata),

        .virtual_sw_input   (virtual_sw_input),
        .virtual_key_input  (virtual_key_input),
        .virtual_seg_output (virtual_seg_output),
        .virtual_led_output (virtual_led_output)
    );

    initial begin
        clk = 1'b0;
        forever #2.5 clk = ~clk;        // 200 MHz
    end

    initial begin
        cnt_clk = 1'b0;
        forever #10 cnt_clk = ~cnt_clk; // 50 MHz
    end

    task automatic perip_write(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [1:0]  mask
    );
        begin
            // 在下降沿准备信号，保证下一个上升沿 DUT 能采样到
            @(negedge clk);
            perip_addr  = addr;
            perip_wdata = data;
            perip_mask  = mask;
            perip_wen   = 1'b1;

            // DUT 在这个上升沿执行写入
            @(posedge clk);
            #1;

            // 写完后释放总线
            @(negedge clk);
            perip_wen   = 1'b0;
            perip_addr  = 32'h0;
            perip_wdata = 32'h0;
            perip_mask  = MASK_WORD;
        end
    endtask

    task automatic perip_read(
        input  logic [31:0] addr,
        output logic [31:0] data
    );
        begin
            // 在下降沿准备读地址
            @(negedge clk);
            perip_addr = addr;
            perip_wen  = 1'b0;

            // perip_bridge / dram_driver 读数据有寄存器延迟
            @(posedge clk);
            @(posedge clk);
            #1;

            data = perip_rdata;

            @(negedge clk);
            perip_addr = 32'h0;
        end
    endtask

    initial begin
        logic [31:0] rdata;

        rst = 1'b1;
        perip_addr  = 32'h0;
        perip_wdata = 32'h0;
        perip_wen   = 1'b0;
        perip_mask  = MASK_WORD;

        virtual_sw_input  = 64'h1234_5678_abcd_ef01;
        virtual_key_input = 8'ha5;

        repeat (10) @(posedge clk);
        rst = 1'b0;

        $display("[PERIP] Reset released.");

        // LED 写测试
        perip_write(LED_ADDR, 32'hdead_beef, MASK_WORD);
        #1;
        if (virtual_led_output !== 32'hdead_beef) begin
            $display("[PERIP] FAIL: LED write error, led=%h", virtual_led_output);
            $finish;
        end

        // SEG 写测试
        perip_write(SEG_ADDR, 32'h0000_1234, MASK_WORD);
        #1;

        // SW0 读测试
        perip_read(SW0_ADDR, rdata);
        if (rdata !== 32'habcd_ef01) begin
            $display("[PERIP] FAIL: SW0 read error, rdata=%h", rdata);
            $finish;
        end

        // SW1 读测试
        perip_read(SW1_ADDR, rdata);
        if (rdata !== 32'h1234_5678) begin
            $display("[PERIP] FAIL: SW1 read error, rdata=%h", rdata);
            $finish;
        end

        // KEY 读测试
        perip_read(KEY_ADDR, rdata);
        if (rdata !== 32'h0000_00a5) begin
            $display("[PERIP] FAIL: KEY read error, rdata=%h", rdata);
            $finish;
        end

        // DRAM word 写读测试
        perip_write(DRAM_BASE + 32'h00, 32'h5566_7788, MASK_WORD);
        perip_read (DRAM_BASE + 32'h00, rdata);
        if (rdata !== 32'h5566_7788) begin
            $display("[PERIP] FAIL: DRAM word test, rdata=%h", rdata);
            $finish;
        end

        // DRAM half-word 写读测试
        perip_write(DRAM_BASE + 32'h04, 32'haaaa_5555, MASK_WORD);
        perip_write(DRAM_BASE + 32'h04, 32'h0000_beef, MASK_HALF);
        perip_read (DRAM_BASE + 32'h04, rdata);
        if (rdata !== 32'haaaa_beef) begin
            $display("[PERIP] FAIL: DRAM half-word test, rdata=%h", rdata);
            $finish;
        end

        // DRAM byte 写读测试
        perip_write(DRAM_BASE + 32'h08, 32'h1122_3344, MASK_WORD);
        perip_write(DRAM_BASE + 32'h08, 32'h0000_00ee, MASK_BYTE);
        perip_read (DRAM_BASE + 32'h08, rdata);
        if (rdata !== 32'h1122_33ee) begin
            $display("[PERIP] FAIL: DRAM byte test, rdata=%h", rdata);
            $finish;
        end

        $display("[PERIP] PASS: all MMIO and DRAM tests passed.");
        $finish;
    end

endmodule