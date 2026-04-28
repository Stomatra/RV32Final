`timescale 1ns / 1ps

module __iverilog_tb_wrapper;
    tb_myCPU dut();
    initial begin
        $dumpfile("D:/digital_twin/digital_twin/digital_twin.srcs/sim_iverilog/tb_myCPU.vcd");
        $dumpvars(0, dut);
        #10000000;
        $display("[SIM] Timeout reached at %0t ns", $time);
        $finish;
    end
endmodule
