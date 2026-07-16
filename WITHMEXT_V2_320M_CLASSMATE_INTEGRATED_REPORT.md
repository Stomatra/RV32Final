# WITHMEXT_V2_320M_CLASSMATE_INTEGRATED_REPORT

## 结论

同学 `new_1` 的 320MHz CPU 提频结构已按“只整合 CPU timing 相关改动”的原则合入当前工程，但官方 `withMext-v2` 在 320MHz 下没有过 timing。

不建议烧录 320MHz 这个 bit，也不要打 `GOOD_320M_WITHMEXT_PASS` tag。

## 保留的当前工程修复

- 保留 `student_top.sv` 中同步 `IROM_BRAM(.clka, .ena, .addra, .douta)` 取指修复。
- 保留 active `withMext-v2` IROM/DRAM。
- 保留 `mainline_virtual_platform_cdc.xdc`。
- 保留 Z_B_SMALL two-cycle 支持，但官方 withMext 构建中 `ENABLE_Z_B_SMALL=0`。
- 没有恢复异步 `IROM(a/spo)`。
- 没有修改 `perip_bridge` 地址映射。
- 没有添加 CPU 内部 false path / multicycle path。

## 320MHz 构建结果

- Bit: `E:/Projects/1Aprojects/RV32Final/final_bits/WITHMEXT_V2_320MHz_TIMING_SWEEP_20260715_200513.bit`
- Bit SHA256: `0DD72E54966D98F45F10BCA7338B5968EF62A207542DDDAC35A862B412ED702D`
- CPU clock: `320.000 MHz`
- Period: `3.125 ns`
- WNS/TNS/WHS: `-0.117 / -6.393 / +0.102`
- DRC errors: `0`
- BIVC/NSTD/UCIO: `0 / 0 / 0`
- IROM SHA256: `0CEA80F2CA36E2672AC8D1E3D0087F88DC24B5A33A177C74B47330B0637C6A1B`
- DRAM SHA256: `D1C6D8F4ADBE80D618CCFCCC0336A9A61B56007B0F44A4E79BDDF71CCAB89C03`
- IROM_BRAM.mif SHA256: `3476CDF70062328F8C3BCFA4A4FD5A2FD3F7632D3F2BBF8234B4160923C4C753`
- ENABLE_Z_B_SMALL: `0`
- XDC: `digital_twin.xdc` + `mainline_virtual_platform_cdc.xdc`
- Resume/open_checkpoint: `0 / 0`

## 320MHz 最差路径

- Source: `student_top_inst/Core_cpu/ex1ex2_alu_b_reg[1]/C`
- Destination: `student_top_inst/Core_cpu/ex1ex2_alu_a_reg[17]/D`
- Logic delay: `0.706 ns`
- Route delay: `2.460 ns`

## 降频探索结果

| Frequency | Actual Clock | WNS | WHS | DRC | Status |
|---|---:|---:|---:|---:|---|
| 320MHz | 320.000MHz | -0.117 | +0.102 | 0 | timing fail |
| 317MHz | 316.667MHz | -0.168 | +0.101 | 0 | timing fail |
| 315MHz | 316.667MHz | -0.168 | +0.101 | 0 | timing fail; PLL 实际仍为 316.667MHz |
| 310MHz | 310.000MHz | +0.025 | +0.067 | 0 | timing pass, 等待上板 |

## 参考报告

- 320MHz timing sweep: `WITHMEXT_V2_320M_TIMING_SWEEP_REPORT.md`
- 317MHz timing sweep: `WITHMEXT_V2_317M_TIMING_SWEEP_REPORT.md`
- 315MHz timing sweep: `WITHMEXT_V2_315M_TIMING_SWEEP_REPORT.md`
- 310MHz timing sweep: `WITHMEXT_V2_310M_TIMING_SWEEP_REPORT.md`
