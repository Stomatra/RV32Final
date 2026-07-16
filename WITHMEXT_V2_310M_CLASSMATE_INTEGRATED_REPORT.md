# WITHMEXT_V2_310M_CLASSMATE_INTEGRATED_REPORT

## 结论

同学 `new_1` 的 320MHz CPU 提频结构与当前工程整合后，官方 `withMext-v2` 在 310.000MHz 下 clean build 通过 timing。

这是本轮整合中目前唯一 WNS >= 0 的频率点。建议下一步优先烧录该 bit 上板验证。

## 输出 bit

- Root bit: `E:/Projects/1Aprojects/RV32Final/WITHMEXT_V2_310MHz_CLASSMATE_INTEGRATED.bit`
- Archived bit: `E:/Projects/1Aprojects/RV32Final/final_bits/WITHMEXT_V2_310MHz_CLASSMATE_INTEGRATED_20260716_094634.bit`
- Bit SHA256: `E9584A7E1466515170DC31BB0BF7240E8302B949353B04C874A3F83DE9E8A039`

## 构建配置

- Top: `top`
- CPU clock target: `310 MHz`
- CPU clock report: `310.000 MHz`
- Period: `3.226 ns`
- active IROM: `withMext-v2`
- active IROM SHA256: `0CEA80F2CA36E2672AC8D1E3D0087F88DC24B5A33A177C74B47330B0637C6A1B`
- active DRAM SHA256: `D1C6D8F4ADBE80D618CCFCCC0336A9A61B56007B0F44A4E79BDDF71CCAB89C03`
- IROM_BRAM.mif SHA256: `3476CDF70062328F8C3BCFA4A4FD5A2FD3F7632D3F2BBF8234B4160923C4C753`
- ENABLE_Z_B_SMALL: `0`
- XDC: `digital_twin.xdc` + `mainline_virtual_platform_cdc.xdc`
- Implementation strategy: `Performance_Explore`
- Directives: opt `Explore`, place `Explore`, phys_opt `AggressiveExplore`, route `Explore`, post-route phys_opt `AggressiveExplore`
- Resume/open_checkpoint: `0 / 0`
- IROM/IP refresh: `IROM=1`, `IROM_BRAM=1`, `DRAM=1`, `PLL=1`

## Timing / DRC

- WNS/TNS/WHS: `+0.025 / 0.000 / +0.067`
- DRC errors: `0`
- BIVC/NSTD/UCIO: `0 / 0 / 0`
- Worst source: `student_top_inst/Core_cpu/ex1ex2_alu_b_reg[1]_replica_4/C`
- Worst destination: `student_top_inst/Core_cpu/ex1ex2_alu_a_reg[29]/D`
- Worst path logic/route delay: `0.670 ns / 2.493 ns`

## 整合说明

实际合入当前工程的是同学 `new_1/myCPU.sv` 中与 320MHz timing 相关的 CPU 内部优化思路：

- EX2 到 EX1 的 ALU 快速前递路径。
- `ex1ex2_alu_op` / `ex1ex2_z_op` fanout 约束提示。
- `ex2_z_wb_data` 提前拆分，减轻 WB mux 路径。
- WB mux 使用更直接的 `unique case` 结构。

没有整包覆盖同学 `new_1` 目录。以下当前工程内容被保留：

- `student_top.sv` 同步 IROM_BRAM 修复。
- `perip_bridge.sv` 地址映射。
- `mainline_virtual_platform_cdc.xdc`。
- `withMext-v2` IROM/DRAM。
- Z_B_SMALL two-cycle 支持，默认关闭。

## 上板预期

烧录 `WITHMEXT_V2_310MHz_CLASSMATE_INTEGRATED.bit` 或归档 bit 后，预期：

- 左侧对号。
- 8 个官方测试灯全亮。
- SEG 显示 `378xxxxx`。

当前状态：timing 已过，尚未上板验证。不要在上板通过前打 `GOOD_310M_WITHMEXT_PASS` tag。

## 参考报告

- Timing sweep report: `WITHMEXT_V2_310M_TIMING_SWEEP_REPORT.md`
- Timing report: `withmext_310m_timing_sweep_build_outputs/timing_WITHMEXT_V2_310MHz_TIMING_SWEEP_20260716_093334.rpt`
- Top 3 timing report: `withmext_310m_timing_sweep_build_outputs/timing_paths_top3_WITHMEXT_V2_310MHz_TIMING_SWEEP_20260716_093334.rpt`
- DRC report: `withmext_310m_timing_sweep_build_outputs/drc_WITHMEXT_V2_310MHz_TIMING_SWEEP_20260716_093334.rpt`
