# Z_B_SMALL_TWO_CYCLE_310M_CLASSMATE_INTEGRATED_REPORT

本报告对应当前 310MHz classmate integrated 高频底座上的 Z_B_SMALL two-cycle 测试构建。
本次只在 `ENABLE_Z_B_SMALL` 打开时关闭 EX2 -> EX1 同拍 ALU 快速旁路，让相关依赖走后一拍前递；官方 withMext-v2 默认关闭 `ENABLE_Z_B_SMALL` 时不进入该改动路径。

- Bit: `E:/Projects/1Aprojects/RV32Final/final_bits/Z_B_SMALL_TWO_CYCLE_TEST_310MHz_CLASSMATE_INTEGRATED_20260716_110232.bit`
- Root bit: `E:/Projects/1Aprojects/RV32Final/Z_B_SMALL_TWO_CYCLE_TEST_310MHz_CLASSMATE_INTEGRATED.bit`
- Bit SHA256: `F0928A8FD2561265E92447CE9296EF74E968C5FF0D4456394D46A8DBEDBC8186`
- IROM SHA256: `D5A762CA186A770E300E3E3B0940B0A6333FB6074F43653EC3361019461B9FFE`
- DRAM SHA256: `D1C6D8F4ADBE80D618CCFCCC0336A9A61B56007B0F44A4E79BDDF71CCAB89C03`
- IROM_BRAM.mif SHA256: `3476CDF70062328F8C3BCFA4A4FD5A2FD3F7632D3F2BBF8234B4160923C4C753`
- CPU clock target: `310.000 MHz`
- CPU clock report: `310.000 MHz`, period `3.226 ns`
- WNS/TNS/WHS: `0.036 / 0.000 / 0.085`
- DRC errors: `0`
- BIVC/NSTD/UCIO: `0 / 0 / 0`
- Worst source: `student_top_inst/Core_cpu/ex1ex2_alu_a_reg[21]/C`
- Worst destination: `student_top_inst/Core_cpu/ex2mem_wb_data_reg[23]/D`
- Worst path logic/route delay: `0.764 ns / 2.355 ns`
- ENABLE_Z_B_SMALL: on, `verilog_define` = `ENABLE_Z_B_SMALL`
- Mainline virtual-platform CDC cut: enabled via `mainline_virtual_platform_cdc.xdc`.
- Synchronous IROM_BRAM preserved: `student_top.sv` instantiates `IROM_BRAM(.clka, .ena, .addra, .douta)`.
- CPU changed files relative to HEAD: ``
- top: `top`
- XDC list: `E:/Projects/1Aprojects/RV32Final/digital_twin.srcs/constrs_1/new/digital_twin.xdc E:/Projects/1Aprojects/RV32Final/digital_twin.srcs/constrs_1/new/mainline_virtual_platform_cdc.xdc`
- compile order: `E:/Projects/1Aprojects/RV32Final/z_b_small_two_cycle_310m_classmate_integrated_build_outputs/compile_order_Z_B_SMALL_TWO_CYCLE_TEST_310MHz_CLASSMATE_INTEGRATED_20260716_110232.txt`
- Resume/open_checkpoint: `0 / 0`
- IROM/IP refresh: `IROM=1`, `IROM_BRAM=1`, `DRAM=1`, `PLL=1`
- Board expectation: `LED=0x000003FF`, `SEG=0000000A`.
- Board result: pass, `LED=0x000003FF`, `SEG=0000000A`.
- Summary txt: `E:/Projects/1Aprojects/RV32Final/z_b_small_two_cycle_310m_classmate_integrated_build_outputs/summary_Z_B_SMALL_TWO_CYCLE_TEST_310MHz_CLASSMATE_INTEGRATED_20260716_110232.txt`
- Timing report: `E:/Projects/1Aprojects/RV32Final/z_b_small_two_cycle_310m_classmate_integrated_build_outputs/timing_Z_B_SMALL_TWO_CYCLE_TEST_310MHz_CLASSMATE_INTEGRATED_20260716_110232.rpt`
- Top 3 timing report: `E:/Projects/1Aprojects/RV32Final/z_b_small_two_cycle_310m_classmate_integrated_build_outputs/timing_paths_top3_Z_B_SMALL_TWO_CYCLE_TEST_310MHz_CLASSMATE_INTEGRATED_20260716_110232.rpt`
- DRC report: `E:/Projects/1Aprojects/RV32Final/z_b_small_two_cycle_310m_classmate_integrated_build_outputs/drc_Z_B_SMALL_TWO_CYCLE_TEST_310MHz_CLASSMATE_INTEGRATED_20260716_110232.rpt`
- Exceptions report: `E:/Projects/1Aprojects/RV32Final/z_b_small_two_cycle_310m_classmate_integrated_build_outputs/exceptions_Z_B_SMALL_TWO_CYCLE_TEST_310MHz_CLASSMATE_INTEGRATED_20260716_110232.rpt`
