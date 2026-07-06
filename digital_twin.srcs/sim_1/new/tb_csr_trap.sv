`timescale 1ns / 1ps

module tb_csr_trap;

    logic clk;
    logic rst;

    logic [11:0] irom_addr;
    logic [31:0] irom_data;

    logic [31:0] perip_addr;
    logic        perip_wen;
    logic [1:0]  perip_mask;
    logic [31:0] perip_wdata;
    logic [31:0] perip_rdata;

    logic [31:0] rom [0:4095];

    myCPU uut (
        .cpu_rst    (rst),
        .cpu_clk    (clk),
        .irom_addr  (irom_addr),
        .irom_data  (irom_data),
        .perip_addr (perip_addr),
        .perip_wen  (perip_wen),
        .perip_mask (perip_mask),
        .perip_wdata(perip_wdata),
        .perip_rdata(perip_rdata)
    );

    assign irom_data   = rom[irom_addr];
    assign perip_rdata = 32'h0;

    initial begin
        clk = 1'b0;
        forever #2.5 clk = ~clk; // 200MHz
    end

    initial begin
        integer i;
        for (i = 0; i < 4096; i = i + 1) begin
            rom[i] = 32'h00000013; // nop
        end

        rom[0]  = 32'h800000b7; // lui   x1, 0x80000
        rom[1]  = 32'h04008093; // addi  x1, x1, 0x40
        rom[2]  = 32'h30509073; // csrrw x0, mtvec, x1
        rom[3]  = 32'h00000073; // ecall
        rom[4]  = 32'h00100393; // addi  x7, x0, 1

        rom[16] = 32'h341022f3; // csrrs x5, mepc, x0
        rom[17] = 32'h34202373; // csrrs x6, mcause, x0
        rom[18] = 32'h00428293; // addi  x5, x5, 4
        rom[19] = 32'h34129073; // csrrw x0, mepc, x5
        rom[20] = 32'h30200073; // mret

        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
    end

    initial begin
        wait (!rst);

        wait (uut.pc_q == 32'h8000_0040);
        $display("[PASS] ecall redirected to mtvec");

        repeat (5) @(posedge clk);

        if (uut.csr_mepc !== 32'h8000_000c) begin
            $display("[FAIL] mepc wrong: %h", uut.csr_mepc);
            $finish;
        end

        if (uut.csr_mcause !== 32'd11) begin
            $display("[FAIL] mcause wrong: %h", uut.csr_mcause);
            $finish;
        end

        $display("[PASS] mepc and mcause correct");

        wait (uut.u_rf.reg_bank[7] == 32'd1);
        $display("[PASS] mret returned to instruction after ecall");

        $finish;
    end

    initial begin
        #2000;
        $display("[FAIL] timeout");
        $finish;
    end

endmodule