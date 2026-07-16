# WITHMEXT_V2_310M_AFTER_Z_SMALL_REGRESSION_REPORT

## 结论

Z_B_SMALL 310MHz 优化后，官方 withMext-v2 在 `ENABLE_Z_B_SMALL=0` 下重新 clean build 通过 timing。

- Bit: `E:/Projects/1Aprojects/RV32Final/final_bits/WITHMEXT_V2_310MHz_TIMING_SWEEP_20260716_111150.bit`
- Root bit: `E:/Projects/1Aprojects/RV32Final/WITHMEXT_V2_310MHz_TIMING_SWEEP.bit`
- Bit SHA256: `FFA67278E3A0B6D2C757537EFB851F2D955E6314FA7EFAF8302AEFB5F552BE54`
- IROM SHA256: `0CEA80F2CA36E2672AC8D1E3D0087F88DC24B5A33A177C74B47330B0637C6A1B`
- DRAM SHA256: `D1C6D8F4ADBE80D618CCFCCC0336A9A61B56007B0F44A4E79BDDF71CCAB89C03`
- IROM_BRAM.mif SHA256: `3476CDF70062328F8C3BCFA4A4FD5A2FD3F7632D3F2BBF8234B4160923C4C753`
- CPU clock: `310.000 MHz`, period `3.226 ns`
- WNS/TNS/WHS: `0.025 / 0.000 / 0.067`
- DRC errors: `0`
- BIVC/NSTD/UCIO: `0 / 0 / 0`
- ENABLE_Z_B_SMALL: `0`
- mainline_virtual_platform_cdc.xdc: used
- Synchronous IROM_BRAM: kept
- Resume/open_checkpoint: `0 / 0`

## Worst Path

- Source: `student_top_inst/Core_cpu/ex1ex2_alu_b_reg[1]_replica_4/C`
- Destination: `student_top_inst/Core_cpu/ex1ex2_alu_a_reg[29]/D`
- Timing report: `E:/Projects/1Aprojects/RV32Final/withmext_310m_timing_sweep_build_outputs/timing_WITHMEXT_V2_310MHz_TIMING_SWEEP_20260716_111150.rpt`
- Top 3 timing report: `E:/Projects/1Aprojects/RV32Final/withmext_310m_timing_sweep_build_outputs/timing_paths_top3_WITHMEXT_V2_310MHz_TIMING_SWEEP_20260716_111150.rpt`
- DRC report: `E:/Projects/1Aprojects/RV32Final/withmext_310m_timing_sweep_build_outputs/drc_WITHMEXT_V2_310MHz_TIMING_SWEEP_20260716_111150.rpt`

## Board Expectation

- 左侧对号
- 8 灯全亮
- `SEG=378xxxxx`

Board result: pass, 左侧对号，8 灯全亮，`SEG=378xxxxx`.
