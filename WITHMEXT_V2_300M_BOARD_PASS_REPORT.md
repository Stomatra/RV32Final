# withMext-v2 300MHz 上板通过报告

## 结论

- 状态：300MHz 官方 `withMext-v2` 已经上板通过。
- 这是目前官方 `withMext-v2` 已经同时满足“timing 通过”和“真板通过”的最高频率。
- 310MHz 虽然 timing 勉强过了，但上板失败，所以不能算成功，不能打 `GOOD_310M_WITHMEXT_PASS` 标签。

## Bit 文件

- bit 路径：`final_bits/WITHMEXT_V2_300MHz_AFTER_300M_INTEGRATION_20260715_121531.bit`
- bit SHA256：`2F476C98795269CCEA8B375FBB4C0A23535071C2CCFD51FC0DDCE36050DE14D7`
- 根目录 bit：`WITHMEXT_V2_300MHz_AFTER_300M_INTEGRATION.bit`

## 构建配置

- 顶层：`top`
- active IROM：`withMext-v2`
- active IROM SHA256：`0CEA80F2CA36E2672AC8D1E3D0087F88DC24B5A33A177C74B47330B0637C6A1B`
- active DRAM SHA256：`D1C6D8F4ADBE80D618CCFCCC0336A9A61B56007B0F44A4E79BDDF71CCAB89C03`
- `IROM_BRAM.mif` SHA256：`3476CDF70062328F8C3BCFA4A4FD5A2FD3F7632D3F2BBF8234B4160923C4C753`
- CPU 时钟：`300.000MHz`
- CPU 周期：`3.333ns`
- `ENABLE_Z_B_SMALL`：关闭
- 约束文件：`digital_twin.xdc` + `mainline_virtual_platform_cdc.xdc`
- 同步取指 `IROM_BRAM` 修复：保留

## Timing 和 DRC

- WNS/TNS/WHS：`+0.010 / 0.000 / +0.095`
- DRC error 数量：`0`
- BIVC/NSTD/UCIO：`0 / 0 / 0`
- 最差路径起点：`student_top_inst/Core_cpu/ex1ex2_alu_op_reg[2]/C`
- 最差路径终点：`student_top_inst/Core_cpu/ex2mem_wb_data_reg[0]/D`
- 最差路径 logic/route delay：`1.476ns / 1.793ns`

## 上板结果

- 左侧对号：亮，通过
- 官方 8 个测试灯：全亮
- 数码管 SEG：`37803643`

## 频率 sweep 记录

- `300MHz`：timing 通过，上板通过。当前最高已验证基线。
- `305MHz`：timing 未通过。
- `310MHz`：WNS 为 `+0.002ns`，timing 勉强通过，但上板失败。不要打 GOOD tag。
- `315MHz`：timing 未通过。
- `320MHz`：已按要求停止 sweep，不再作为候选。

## 后续判断

当前能放心作为官方 `withMext-v2` 高频基线的是：

`final_bits/WITHMEXT_V2_300MHz_AFTER_300M_INTEGRATION_20260715_121531.bit`

后续只有同时满足下面条件时，才应该打新的 GOOD tag：

1. timing WNS >= 0；
2. DRC = 0；
3. 真板左侧对号亮；
4. 官方 8 灯全亮；
5. SEG 显示 `378xxxxx`。
