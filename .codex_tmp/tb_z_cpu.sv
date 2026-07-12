`timescale 1ns / 1ps

module tb_z_cpu;
    logic        clk;
    logic        rst;
    logic [11:0] irom_addr;
    logic [31:0] irom_data;
    logic [31:0] perip_addr;
    logic        perip_wen;
    logic [1:0]  perip_mask;
    logic [31:0] perip_wdata;

    logic [31:0] rom [0:255];

    myCPU dut (
        .cpu_rst    (rst),
        .cpu_clk    (clk),
        .irom_addr  (irom_addr),
        .irom_data  (irom_data),
        .perip_addr (perip_addr),
        .perip_wen  (perip_wen),
        .perip_mask (perip_mask),
        .perip_wdata(perip_wdata),
        .perip_rdata(32'h0)
    );

    assign irom_data = rom[irom_addr[7:0]];

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        for (int i = 0; i < 256; i++) begin
            rom[i] = 32'h0000_0013;
        end

        rom[0] = 32'h00f0_0093; // addi  x1, x0, 15
        rom[1] = 32'h0030_0113; // addi  x2, x0, 3
        rom[2] = 32'h4020_f1b3; // andn  x3, x1, x2
        rom[3] = 32'h0011_8213; // addi  x4, x3, 1
        rom[4] = 32'h2850_9293; // bseti x5, x1, 5
        rom[5] = 32'h0820_c333; // pack  x6, x1, x2

        rst = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        repeat (80) @(posedge clk);

        check_reg(3, 32'd12,       "andn writeback");
        check_reg(4, 32'd13,       "z result forwarding");
        check_reg(5, 32'd47,       "bseti writeback");
        check_reg(6, 32'h0003_000f, "pack writeback");

        $display("[TB] PASS: z_cpu smoke");
        $finish;
    end

    task automatic check_reg(input int idx, input logic [31:0] expected, input string name);
        begin
            if (dut.u_rf.reg_bank[idx] !== expected) begin
                $error("%s failed: x%0d=%08h expected=%08h",
                       name, idx, dut.u_rf.reg_bank[idx], expected);
                $finish;
            end
        end
    endtask
endmodule
