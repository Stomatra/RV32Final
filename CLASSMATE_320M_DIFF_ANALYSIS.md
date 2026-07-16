# CLASSMATE_320M_DIFF_ANALYSIS

## 对比范围

- 当前基线：`32a508c3fc30cc403ea908f595a12d38a0af1ce7`，即 300MHz withMext-v2 上板成功快照。
- 同学代码目录：`digital_twin.srcs/new_1/new/`
- 整合分支：`feature/integrate-classmate-320m`

## 总体结论

`new_1` 里真正值得迁入主线的是 `myCPU.sv` 中的 320MHz timing 优化。`student_top.sv` 虽然也例化了同步 `IROM_BRAM`，但包含大量 debug/显示选择逻辑，不适合覆盖当前已验证主线。`perip_bridge.sv` 地址映射一致，但读数据打一拍实现和当前不同，也不覆盖。`z_light_decode.sv` 是旧版，不含 Z_B_SMALL，必须保留当前版本。

## 关键文件结论

| 文件 | 差异结论 | 整合动作 |
|---|---|---|
| `myCPU.sv` | 同学版移除了 Z_B_SMALL，但加入普通 ALU EX2->EX1 快速旁路、控制信号 fanout hint、Z 写回拆分等 320MHz 优化。 | 只移植这些 timing 优化，保留当前 Z_B_SMALL two-cycle。 |
| `student_top.sv` | 同学版含同步 `IROM_BRAM`，但还含 debug_sticky/debug_seg_output/virtual_sw 选择等大量调试逻辑。 | 不覆盖，保留当前主线同步 `IROM_BRAM` 修复。 |
| `perip_bridge.sv` | 地址一致：SEG=0x80200020、LED=0x80200040、CNT=0x80200050、DRAM=0x80100000-0x8013FFFF。读数据寄存方式不同。 | 不覆盖，保留当前 300MHz 已验证版本。 |
| `z_light_decode.sv` | 同学版基本是旧 Z_LIGHT decode，缺少 Z_B_SMALL 10 条指令。 | 不覆盖，保留当前带 `ENABLE_Z_B_SMALL` 宏的版本。 |
| `dram_driver.sv` | 与当前基本一致，用于 withMext-v2 DRAM 初始化。 | 不覆盖。 |
| `top.sv/display_seg.sv/counter.sv/uart.sv/twin_controller.sv` | 不是 320MHz CPU 核心 timing 关键点。 | 不覆盖。 |

## 已移植到当前 `myCPU.sv` 的 320MHz 点

1. 给 `ex1ex2_alu_op` 增加 `(* max_fanout = 16 *)`。
2. 给 `ex1ex2_z_op` 增加 `(* max_fanout = 32 *)`。
3. 增加 `ex2_z_wb_data = ex2_z_supported ? ex2_z_result : 32'h0`，拆开 Z 写回支持判断。
4. 打开普通 ALU 结果的 `IDEX1 -> EX1/EX2` 快速前递判定：仅 `WB_SRC_ALU`、非 M、非 helper、rd 非 x0 可走 EX2->EX1。
5. `slow_result_ex1_hazard` 排除可快速前递的普通 ALU 结果，其余结果仍等待到 EX2/MEM。
6. EX1 operand mux 增加 `idex1_fwd_rs*_from_ex2 ? ex2_alu_y` 分支。
7. WB mux 改成 `unique case`，并优先列出 Z/CSR 结果。

## 保留的当前工程修复

1. `student_top.sv` 仍使用同步 `IROM_BRAM(.clka, .ena, .addra, .douta)`，不恢复异步 `IROM(a/spo)`。
2. `withMext-v2` active IROM/DRAM 配置不变。
3. `mainline_virtual_platform_cdc.xdc` 保留。
4. `Z_B_SMALL` two-cycle 代码保留，但默认 `ENABLE_Z_B_SMALL` 关闭。
5. 没有覆盖 `perip_bridge` 地址映射。
6. 没有改 M 扩展模块、IROM_BRAM IP、HDMI/UART debug 代码。

## 风险点

- 新打开的普通 ALU EX2->EX1 快速旁路可能改善 timing/性能，但也可能影响相邻 RAW 冒险行为，需要先跑官方 withMext-v2。
- Z_B_SMALL pending 逻辑仍通过 `stall_z_b_small` hold 前端；官方 withMext-v2 默认关闭，不应影响主线。
- 若 320MHz timing 失败，优先回退到 317/315/310，而不是改外设或加 CPU false path。
