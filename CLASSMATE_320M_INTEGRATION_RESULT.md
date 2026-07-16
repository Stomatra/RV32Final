# CLASSMATE_320M_INTEGRATION_RESULT

## 总结

已完成同学 `new_1` 代码与当前工程的安全整合。整合后，官方 `withMext-v2` 在 320/317/315MHz 未过 timing，在 310MHz 通过 timing。

当前建议优先上板验证 310MHz：

- Bit: `E:/Projects/1Aprojects/RV32Final/final_bits/WITHMEXT_V2_310MHz_CLASSMATE_INTEGRATED_20260716_094634.bit`
- SHA256: `E9584A7E1466515170DC31BB0BF7240E8302B949353B04C874A3F83DE9E8A039`
- WNS/TNS/WHS: `+0.025 / 0.000 / +0.067`
- DRC: `0`

## 整合文件

本轮真正整合到主线 CPU 的文件：

| 文件 | 处理方式 | 说明 |
|---|---|---|
| `digital_twin.srcs/sources_1/new/myCPU.sv` | 修改 | 合入同学 320MHz CPU timing 优化，同时保留 Z_B_SMALL two-cycle 代码，默认关闭 |
| `digital_twin.srcs/sources_1/imports/new/z_light_unit.sv` | 保留当前版本 | 保留 Z_B_SMALL 支持和现有 Z_LIGHT 单元 |

没有覆盖：

- `student_top.sv`
- `top.sv`
- `perip_bridge.sv`
- `dram_driver.sv`
- `display_seg.sv`
- `digital_twin.xdc`
- `mainline_virtual_platform_cdc.xdc`

## 保留的当前工程修复

- 同步 `IROM_BRAM` 取指修复保留。
- `withMext-v2` IROM/DRAM 保留。
- `mainline_virtual_platform_cdc.xdc` 保留。
- Z_B_SMALL two-cycle 支持保留。
- `ENABLE_Z_B_SMALL` 官方 withMext 构建默认关闭。
- 没有恢复异步 `IROM(a/spo)`。
- 没有修改 `perip_bridge` 地址。
- 没有添加 CPU 内部 false path / multicycle。

## 频率结果

| Frequency | Actual Clock | WNS | WHS | DRC | Bit SHA256 | 结论 |
|---|---:|---:|---:|---:|---|---|
| 320MHz | 320.000MHz | -0.117 | +0.102 | 0 | `0DD72E54966D98F45F10BCA7338B5968EF62A207542DDDAC35A862B412ED702D` | timing fail |
| 317MHz | 316.667MHz | -0.168 | +0.101 | 0 | `EA9AB6420EC434C5A33B3186A4AB53DC97B11A0619BF8D2EBE69A6AE2C681C99` | timing fail |
| 315MHz | 316.667MHz | -0.168 | +0.101 | 0 | `E794BA3D3CC0D9AA8C7186D992F28F8DE75B9AC15131133E56E1CA10095B84DF` | timing fail，PLL 实际仍为 316.667MHz |
| 310MHz | 310.000MHz | +0.025 | +0.067 | 0 | `E9584A7E1466515170DC31BB0BF7240E8302B949353B04C874A3F83DE9E8A039` | timing pass，待上板 |

## 下一步

1. 上板测试 `WITHMEXT_V2_310MHz_CLASSMATE_INTEGRATED_20260716_094634.bit`。
2. 如果上板出现左侧对号、8 灯全亮、SEG=`378xxxxx`，再考虑提交和打 `GOOD_310M_WITHMEXT_PASS`。
3. 如果 310MHz 上板失败，优先检查官方 test 输出和 active bit，暂时不要继续冲 320MHz。
