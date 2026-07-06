`timescale 1ns / 1ps

module tb_myCPU_reg;
    // 裸 myCPU 核心测试平台。
    // 在 testbench 内手工建立 IROM/DRAM/MMIO 模型，用于直接观察 CPU 对外总线和寄存器级行为。
    localparam int CPU_CLK_PERIOD_NS = 20;
    localparam int IROM_DEPTH = 4096;
    localparam int DRAM_DEPTH = 65536;
    localparam logic [31:0] RESET_PC = 32'h8000_0000;

    localparam logic [31:0] DRAM_ADDR_START = 32'h8010_0000;
    localparam logic [31:0] DRAM_ADDR_END   = 32'h8013_FFFF;
    localparam logic [31:0] SW0_ADDR        = 32'h8020_0000;
    localparam logic [31:0] SW1_ADDR        = 32'h8020_0004;
    localparam logic [31:0] KEY_ADDR        = 32'h8020_0010;
    localparam logic [31:0] SEG_ADDR        = 32'h8020_0020;
    localparam logic [31:0] LED_ADDR        = 32'h8020_0040;
    localparam logic [31:0] CNT_ADDR        = 32'h8020_0050;

    logic        cpu_clk;
    logic        cpu_rst;
    logic [11:0] irom_addr;
    logic [31:0] irom_data;
    logic [31:0] perip_addr;
    logic        perip_wen;
    logic [1:0]  perip_mask;
    logic [31:0] perip_wdata;
    logic [31:0] perip_rdata;

    logic [31:0] irom_mem [0:IROM_DEPTH-1];
    logic [31:0] dram_mem [0:DRAM_DEPTH-1];

    logic [63:0] virtual_sw;
    logic [7:0]  virtual_key;
    logic [31:0] led_reg;
    logic [31:0] seg_reg;

    logic        cnt_start;
    logic [15:0] cnt_1ms;
    logic [31:0] cnt_ms;
    logic        cnt_wen;

    logic [31:0] dram_word;
    logic [31:0] dram_read_data;
    logic [31:0] mmio_read_data;
    logic [31:0] cycle_count;
    logic [31:0] fetch_pc;

    string irom_mem_path;
    string dram_mem_path;
    string vcd_path;
    integer timeout_ns;
    integer idx;
    bit verbose;
    logic [31:0] sw_lo_arg;
    logic [31:0] sw_hi_arg;

    myCPU dut (
        .cpu_rst    (cpu_rst),
        .cpu_clk    (cpu_clk),
        .irom_addr  (irom_addr),
        .irom_data  (irom_data),
        .perip_addr (perip_addr),
        .perip_wen  (perip_wen),
        .perip_mask (perip_mask),
        .perip_wdata(perip_wdata),
        .perip_rdata(perip_rdata)
    );

    assign fetch_pc = {RESET_PC[31:14], irom_addr, 2'b00};

    // 根据访问粒度和字内偏移，从 DRAM 存储字中还原 CPU 实际看到的返回值。
    function automatic logic [31:0] dram_read_mux(
        input logic [31:0] word,
        input logic [1:0]  mask,
        input logic [1:0]  offset
    );
        begin
            case (mask)
                2'b00: begin
                    case (offset)
                        2'b00: dram_read_mux = {24'h0, word[7:0]};
                        2'b01: dram_read_mux = {24'h0, word[15:8]};
                        2'b10: dram_read_mux = {24'h0, word[23:16]};
                        default: dram_read_mux = {24'h0, word[31:24]};
                    endcase
                end
                2'b01: dram_read_mux = offset[1] ? {16'h0, word[31:16]} : {16'h0, word[15:0]};
                default: dram_read_mux = word;
            endcase
        end
    endfunction

    // 根据写掩码把字节/半字/整字写操作折叠到 32bit 存储字上。
    function automatic logic [31:0] dram_write_mux(
        input logic [31:0] old_word,
        input logic [31:0] new_word,
        input logic [1:0]  mask,
        input logic [1:0]  offset
    );
        begin
            case (mask)
                2'b10: dram_write_mux = new_word;
                2'b01: dram_write_mux = offset[1] ? {new_word[15:0], old_word[15:0]} : {old_word[31:16], new_word[15:0]};
                2'b00: begin
                    case (offset)
                        2'b00: dram_write_mux = {old_word[31:8], new_word[7:0]};
                        2'b01: dram_write_mux = {old_word[31:16], new_word[7:0], old_word[7:0]};
                        2'b10: dram_write_mux = {old_word[31:24], new_word[7:0], old_word[15:0]};
                        default: dram_write_mux = {new_word[7:0], old_word[23:0]};
                    endcase
                end
                default: dram_write_mux = new_word;
            endcase
        end
    endfunction

    always begin
        #(CPU_CLK_PERIOD_NS / 2) cpu_clk = ~cpu_clk;
    end

    initial begin
        cpu_clk = 1'b0;
        cpu_rst = 1'b1;

        virtual_sw = 64'h0;
        virtual_key = 8'h0;
        led_reg = 32'h0;
        seg_reg = 32'h0;

        cnt_start = 1'b0;
        cnt_1ms = 16'h0;
        cnt_ms = 32'h0;
        cycle_count = 32'h0;
        verbose = $test$plusargs("verbose");

        for (idx = 0; idx < IROM_DEPTH; idx = idx + 1) begin
            irom_mem[idx] = 32'h0000_0013;
        end

        for (idx = 0; idx < DRAM_DEPTH; idx = idx + 1) begin
            dram_mem[idx] = 32'h0;
        end

        if ($value$plusargs("irom=%s", irom_mem_path)) begin
            $display("[TB] Loading IROM from %s", irom_mem_path);
            $readmemh(irom_mem_path, irom_mem);
        end else begin
            $display("[TB] No IROM image provided, using NOP-filled ROM");
        end

        if ($value$plusargs("dram=%s", dram_mem_path)) begin
            $display("[TB] Loading DRAM from %s", dram_mem_path);
            $readmemh(dram_mem_path, dram_mem);
        end else begin
            $display("[TB] No DRAM image provided, using zero-filled DRAM");
        end

        if ($value$plusargs("sw_lo=%h", sw_lo_arg)) begin
            virtual_sw[31:0] = sw_lo_arg;
        end
        if ($value$plusargs("sw_hi=%h", sw_hi_arg)) begin
            virtual_sw[63:32] = sw_hi_arg;
        end
        if ($value$plusargs("key=%h", virtual_key)) begin end

        if ($value$plusargs("vcd=%s", vcd_path)) begin
            $dumpfile(vcd_path);
            $dumpvars(0, tb_myCPU_reg);
        end

        if (!$value$plusargs("timeout_ns=%d", timeout_ns)) begin
            timeout_ns = 10_000_000;
        end

        repeat (10) @(posedge cpu_clk);
        cpu_rst = 1'b0;
        $display("[TB] Reset released at %0.1f ns", $realtime);
    end

    initial begin
        if (!$value$plusargs("timeout_ns=%d", timeout_ns)) begin
            timeout_ns = 10_000_000;
        end
        #timeout_ns;
        $display("[TB] Timeout at %0.1f ns", $realtime);
        $display("[TB] Summary cycles=%0d pc=%h led=%h seg=%h cnt_ms=%0d", cycle_count, fetch_pc, led_reg, seg_reg, cnt_ms);
        $finish;
    end

    always_ff @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cycle_count <= 32'h0;
        end else begin
            cycle_count <= cycle_count + 1'b1;
        end
    end

    assign irom_data = irom_mem[irom_addr];
    assign dram_word = ((perip_addr >= DRAM_ADDR_START) && (perip_addr <= DRAM_ADDR_END)) ? dram_mem[perip_addr[17:2]] : 32'h0;
    assign dram_read_data = dram_read_mux(dram_word, perip_mask, perip_addr[1:0]);

    always_comb begin
        case (perip_addr)
            SW0_ADDR: mmio_read_data = virtual_sw[31:0];
            SW1_ADDR: mmio_read_data = virtual_sw[63:32];
            KEY_ADDR: mmio_read_data = {24'h0, virtual_key};
            SEG_ADDR: mmio_read_data = seg_reg;
            CNT_ADDR: mmio_read_data = cnt_ms;
            default:  mmio_read_data = 32'hDEAD_BEEF;
        endcase
    end

    // 1-cycle registered perip_rdata -- matches hardware BRAM + perip_bridge
    logic [31:0] perip_rdata_comb;
    assign perip_rdata_comb = ((perip_addr >= DRAM_ADDR_START) && (perip_addr <= DRAM_ADDR_END)) ? dram_read_data :
                              (!perip_wen) ? mmio_read_data : 32'h0;
    always_ff @(posedge cpu_clk) begin
        perip_rdata <= perip_rdata_comb;
    end

    assign cnt_wen = perip_wen && (perip_addr == CNT_ADDR);

    always_ff @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cnt_start <= 1'b0;
        end else if (cnt_wen && (perip_wdata == 32'h8000_0000)) begin
            cnt_start <= 1'b1;
        end else if (cnt_wen && (perip_wdata == 32'hFFFF_FFFF)) begin
            cnt_start <= 1'b0;
        end
    end

    always_ff @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cnt_1ms <= 16'h0;
        end else if (cnt_start) begin
            if (cnt_1ms == 16'd49999) begin
                cnt_1ms <= 16'h0;
            end else begin
                cnt_1ms <= cnt_1ms + 1'b1;
            end
        end else begin
            cnt_1ms <= 16'h0;
        end
    end

    always_ff @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            cnt_ms <= 32'h0;
        end else if (cnt_start && (cnt_1ms == 16'd49999)) begin
            cnt_ms <= cnt_ms + 1'b1;
        end
    end

    always @(posedge cpu_clk) begin
        if (perip_wen) begin
            if ((perip_addr >= DRAM_ADDR_START) && (perip_addr <= DRAM_ADDR_END)) begin
                dram_mem[perip_addr[17:2]] <= dram_write_mux(dram_word, perip_wdata, perip_mask, perip_addr[1:0]);
            end else begin
                case (perip_addr)
                    LED_ADDR: led_reg <= perip_wdata;
                    SEG_ADDR: seg_reg <= perip_wdata;
                    default: begin end
                endcase
            end

            if (verbose) begin
                $display("[TB] write @%0.1f ns addr=%h mask=%0d data=%h", $realtime, perip_addr, perip_mask, perip_wdata);
            end
        end
    end

    always @(posedge cpu_clk) begin
        if (!cpu_rst && verbose && !perip_wen && (perip_addr == SEG_ADDR || perip_addr == LED_ADDR || perip_addr == CNT_ADDR)) begin
            $display("[TB] read  @%0.1f ns addr=%h data=%h", $realtime, perip_addr, perip_rdata);
        end
    end
endmodule