# 从 283MHz 成功基线到当前版本的改动总结

这份报告的目的：给后续“把 Z_B_SMALL two-cycle 精确移植到同学 317MHz 高频 CPU”做参考。

重点提醒：不要整文件覆盖同学的 `myCPU.sv`。只移植 Z_B_SMALL 相关的小块逻辑。

## 1. 对比范围

- 对比起点 tag：`GOOD_283M_WITHMEXT_PASS`
- 起点 commit：`c5d9fd2`
- 起点说明：`perf: pass withMext-v2 at 283MHz`
- 当前 HEAD：`10f5747abe343fe6ad37279c1611d38892738166`
- 当前 HEAD 说明：`feat: pipeline Z_B_SMALL execution into two cycles`
- 当前分支：`fix/sync-irom-bram-baseline`

从 `GOOD_283M_WITHMEXT_PASS` 到当前 HEAD，已经提交进去的主要改动文件是：

- `digital_twin.srcs/sources_1/new/myCPU.sv`
- `digital_twin.srcs/sources_1/imports/test_src/irom-z-b-small-test.coe`
- `scripts/gen_irom_z_b_small_test.py`
- `build_z_b_small_two_cycle_test_200m.tcl`
- `build_z_b_small_two_cycle_test_283m_cdc_cut.tcl`
- `build_z_b_small_two_cycle_test_283m_opt1.tcl`
- `build_z_b_small_two_cycle_test_300m_cdc_cut.tcl`
- `build_z_b_small_two_cycle_test_300m_opt1.tcl`
- `build_withmext_v2_283m_after_z_two_cycle.tcl`
- Z_B_SMALL / withMext timing 报告 markdown

当前工作区还有很多旧调试文件删除项、未跟踪文件、临时输出目录。这些不是本次总结对象，不要把它们当成要移植的内容。

当前 HEAD 之后还有一批未提交的 300MHz 同学代码整合改动，主要涉及：

- `myCPU.sv`
- `top.sv`
- `student_top.sv`
- `perip_bridge.sv`
- `dram_driver.sv`
- `mainline_virtual_platform_cdc.xdc`
- `pll.xci`
- `digital_twin.xpr`

这批 300MHz 整合改动属于“官方 withMext-v2 提频路径”，不是“Z_B_SMALL 最小移植补丁”。后续移植 Z_B_SMALL 时不要直接拿当前脏工作区整包打补丁。

## 2. 总体结论

从 283MHz 官方 `withMext-v2` 成功基线之后，主要新增的是第二类 Z 指令集合，也就是 `Z_B_SMALL`。

最开始 Z_B_SMALL 是单拍组合逻辑，rotate / result mux 路径太长。后来改成 two-cycle，两拍执行后，283.333MHz timing 和上板都通过了。

官方 `withMext-v2` 默认仍然关闭 `ENABLE_Z_B_SMALL`。只有 Z_B_SMALL 测试脚本会显式打开这个宏。

同步 `IROM_BRAM` 取指修复仍然保留，没有退回到原来的异步 `IROM(a/spo)`。

已经提交的 Z_B_SMALL two-cycle 改动没有修改：

- M 扩展功能；
- `perip_bridge` 地址映射；
- DRAM 初始化内容；
- HDMI；
- UART。

## 3. `myCPU.sv` 改动总结

### A. 新增的 Z_B_SMALL 指令

一共 10 条：

- `sh1add`
- `sh2add`
- `sh3add`
- `min`
- `minu`
- `max`
- `maxu`
- `rol`
- `ror`
- `rori`

对应的内部 Z 操作码是：

- `ZOP_SH1ADD = 6'd21`
- `ZOP_SH2ADD = 6'd22`
- `ZOP_SH3ADD = 6'd23`
- `ZOP_MIN = 6'd24`
- `ZOP_MINU = 6'd25`
- `ZOP_MAX = 6'd26`
- `ZOP_MAXU = 6'd27`
- `ZOP_ROL = 6'd28`
- `ZOP_ROR = 6'd29`
- `ZOP_RORI = 6'd30`

### B. Decode 方式

Z_B_SMALL 复用原来的 Z_LIGHT decode / 写回通路。

R-type 指令：

- opcode：`0110011`
- 使用 `rs1`
- 使用 `rs2`
- 写 `rd`
- 写回来源是 `WB_SRC_Z`

`rori` 是 I-type：

- opcode：`0010011`
- funct7：`0110000`
- funct3：`101`
- shamt 来自 `instr[24:20]`
- 使用 `rs1`
- 不使用 `rs2`
- 写 `rd`
- 写回来源是 `WB_SRC_Z`

这里最容易出错的是 `rori`。它不能被当成使用 `rs2`，否则会产生假的 load-use hazard。

### C. 新增的控制/数据寄存器

当前 `myCPU.sv` 里的真实信号名如下：

- `ex2_is_z_b_small`
- `z_b_small_start`
- `stall_z_b_small`
- `hold_ex1ex2`
- `z_b_small_pending_q`
- `z_b_small_op_q`
- `z_b_small_rd_q`
- `z_b_small_rf_we_q`
- `z_b_small_wb_sel_q`
- `z_b_small_pc_q`
- `z_b_small_partial_q`
- `z_b_small_rs1_q`
- `z_b_small_rs2_q`
- `z_b_small_shamt_hi_q`
- `z_b_small_signed_lt_q`
- `z_b_small_unsigned_lt_q`
- `z_b_small_eff_shamt`
- `z_b_small_rot_s0`
- `z_b_small_rot_s1`
- `z_b_small_rot_s2`
- `z_b_small_stage1_partial`
- `z_b_small_stage2_rot_s3`
- `z_b_small_stage2_rot_s4`
- `z_b_small_final_result`

辅助函数：

- `z_b_small_op_is_small(z_op)`

这个函数判断当前 Z op 是否属于第二类 Z 小集合。

### D. two-cycle 执行逻辑

Z_B_SMALL 不再单拍完成，而是拆成 start 拍和 pending 拍。

start 拍做的事情：

- 当一条有效的 Z_B_SMALL 指令到达 EX2，并且当前没有 pending 指令时，`z_b_small_start` 拉高。
- `stall_z_b_small` 拉高，让前端、ID/EX、EX1/EX2 暂停一拍。
- EX2/MEM 插入 bubble，避免把半成品当成真正结果写回。
- 保存当前指令的信息：
  - op；
  - rd；
  - rf_we；
  - wb_sel；
  - pc；
  - rs1；
  - rs2；
  - 比较结果；
  - rotate 高位 shamt；
  - 第一阶段 partial result。

pending 拍做的事情：

- `z_b_small_pending_q` 拉高，表示上一拍有一条 Z_B_SMALL 指令等待完成。
- 根据保存的寄存器计算最终结果 `z_b_small_final_result`。
- 把保存的 rd / rf_we / wb_sel / pc 和最终结果写入 EX2/MEM。
- 如果没有 load stall 或 M stall，就清掉 pending。

具体拆分方式：

- `sh1add/sh2add/sh3add`：
  - start 拍保存固定左移后的 `rs1`；
  - pending 拍再加保存的 `rs2`。

- `rol/ror/rori`：
  - start 拍按 shamt 低 3 位 `[2:0]` 做旋转；
  - pending 拍按 shamt 高 2 位 `[4:3]` 继续旋转。

- `min/minu/max/maxu`：
  - start 拍保存 rs1、rs2 和比较结果；
  - pending 拍根据比较结果选择最终输出。

这样做的目的：切断原来 EX2 里 rotate / Z result mux / writeback 的长组合路径。

### E. 对普通 Z_LIGHT 的影响

- 普通 Z_LIGHT 仍然走原来的单拍 Z unit。
- `z_light_unit` 在当前 `myCPU.sv` 中实例化时传入 `ENABLE_Z_B_SMALL(1'b0)`。
- 也就是说，Z_B_SMALL 不在 `z_light_unit` 里算，而是在 CPU 里单独 two-cycle 处理。
- 如果没有定义 `ENABLE_Z_B_SMALL`，`CPU_ENABLE_Z_B_SMALL = 1'b0`，two-cycle 路径不会启动。

### F. hazard / forwarding 影响

- R-type Z_B_SMALL 正确标记为使用 `rs1` 和 `rs2`。
- `rori` 正确标记为只使用 `rs1`，不使用 `rs2`。
- `stall_z_b_small` 接入 `fetch_stall` 和 ID/EX hold 逻辑。
- start 拍插 bubble，pending 拍再把结果送到 EX2/MEM。
- 这样后一条依赖 Z_B_SMALL 结果的指令，可以继续复用现有 EX2/MEM 或 MEM/WB forwarding。
- `x0` 写回无效仍然依赖原来的 `rd != 0` 保护逻辑。

## 4. 测试 IROM 改动

- 测试 IROM：`digital_twin.srcs/sources_1/imports/test_src/irom-z-b-small-test.coe`
- 当前 SHA256：`D5A762CA186A770E300E3E3B0940B0A6333FB6074F43653EC3361019461B9FFE`
- 生成脚本：`scripts/gen_irom_z_b_small_test.py`
- 生成脚本 SHA256：`A65490244D76C2CC0410E283867F2FBE42A3DC8275B19715B8260EBAEE0ADBA9`

测试覆盖：

- 10 条 Z_B_SMALL 指令的基本功能；
- `sh1add` 的紧邻依赖使用；
- `ror` 的紧邻依赖使用；
- `rori` 的紧邻依赖使用；
- branch 依赖 Z_B_SMALL 结果；
- 写 `x0` 不应改变寄存器状态。

最终预期：

- `LED = 0x000003FF`
- `SEG = 0000000A`

## 5. 构建脚本改动

已提交的 two-cycle Z_B_SMALL 脚本：

| 脚本 | 是否打开 ENABLE_Z_B_SMALL | 使用的 IROM | 目标频率 | 说明 |
|---|---:|---|---:|---|
| `build_z_b_small_two_cycle_test_200m.tcl` | 是 | `irom-z-b-small-test.coe` | 200MHz | Z_B_SMALL 功能测试 |
| `build_z_b_small_two_cycle_test_283m_cdc_cut.tcl` | 是 | `irom-z-b-small-test.coe` | 283.333MHz | 第一版 283MHz timing 检查 |
| `build_z_b_small_two_cycle_test_283m_opt1.tcl` | 是 | `irom-z-b-small-test.coe` | 283.333MHz | 已 timing 通过并上板通过 |
| `build_z_b_small_two_cycle_test_300m_cdc_cut.tcl` | 是 | `irom-z-b-small-test.coe` | 300MHz | 探索用 |
| `build_z_b_small_two_cycle_test_300m_opt1.tcl` | 是 | `irom-z-b-small-test.coe` | 300MHz | timing 未过 |
| `build_withmext_v2_283m_after_z_two_cycle.tcl` | 否 | `withMext-v2` | 283.333MHz | 官方回归测试 |

HEAD 之后还有两个和 300MHz sweep 相关的脚本：

- `build_withmext_v2_300m_after_300m_integration.tcl`
- `build_withmext_v2_timing_sweep.tcl`

这两个是官方 `withMext-v2` 提频探索脚本，默认 `ENABLE_Z_B_SMALL` 关闭，不属于 Z_B_SMALL 最小功能移植范围。

## 6. 约束改动

- Z_B_SMALL two-cycle 本身没有新增 CPU 内部 false path。
- Z_B_SMALL two-cycle 本身没有新增 multicycle path。
- 主线构建使用 `digital_twin.xdc` + `mainline_virtual_platform_cdc.xdc`。
- `mainline_virtual_platform_cdc.xdc` 是虚拟平台 SW/KEY/LED/SEG 跨时钟同步寄存器的 CDC cut。
- 这个 CDC cut 不是给 Z_B_SMALL 结果路径开的后门。
- Z_B_SMALL rotate/result/writeback 路径没有被 false path 或 multicycle 掩盖。

## 7. 已验证结果

### A. Z_B_SMALL two-cycle 200MHz

- bit：`final_bits/Z_B_SMALL_TWO_CYCLE_TEST_200MHz_20260714_204301.bit`
- bit SHA256：`20456CC3DF0F80958FE28928F219F3FC72745D83F1A485636985FA0F319C7056`
- WNS/WHS：`+0.156 / +0.074`
- 上板结果：`LED=0x000003FF`，`SEG=0000000A`

### B. 加入 two-cycle 后的官方 withMext-v2 283.333MHz 回归

- bit：`final_bits/WITHMEXT_V2_283MHz_AFTER_Z_TWO_CYCLE_20260715_091114.bit`
- bit SHA256：`51A34ED9CF9AF074C24C634888C43A85A75A686BDA7FE8EB955DC59DCB3F14C5`
- WNS/WHS：`+0.002 / +0.085`
- 上板结果：左侧对号，8 灯全亮，`SEG=37803245`

### C. Z_B_SMALL two-cycle 283.333MHz OPT1

- bit：`final_bits/Z_B_SMALL_TWO_CYCLE_TEST_283MHz_OPT1_20260715_092856.bit`
- bit SHA256：`B444CAABA48B745443C6913BF0752F2FA9FFF9AC93E756AA9F8B3EA9E343FE49`
- WNS/WHS：`+0.025 / +0.023`
- 上板结果：`LED=0x000003FF`，`SEG=0000000A`

### D. Z_B_SMALL 300MHz

- bit：`final_bits/Z_B_SMALL_TWO_CYCLE_TEST_300MHz_OPT1_20260715_094501.bit`
- bit SHA256：`7E039CF911B1E43923903F90A8BA3316295AFF65229088BFD16BCE835E11CFC0`
- WNS/TNS/WHS：`-0.356 / -154.553 / +0.084`
- 最差路径起点：`student_top_inst/bridge_inst/dram_driver_inst/dram_lane3_reg_0_2/CLKARDCLK`
- 最差路径终点：`student_top_inst/bridge_inst/perip_rdata_q_reg[26]/D`
- 结论：300MHz 下 Z_B_SMALL timing 未过，但瓶颈已经不是 rotate/Z result，而是 DRAM/perip 读数据返回路径。

### E. 官方 withMext-v2 300MHz

- bit：`final_bits/WITHMEXT_V2_300MHz_AFTER_300M_INTEGRATION_20260715_121531.bit`
- bit SHA256：`2F476C98795269CCEA8B375FBB4C0A23535071C2CCFD51FC0DDCE36050DE14D7`
- WNS/WHS：`+0.010 / +0.095`
- 上板结果：左侧对号，8 灯全亮，`SEG=37803643`
- `ENABLE_Z_B_SMALL`：关闭

## 8. 移植到同学 317MHz CPU 的建议

最小移植清单：

- `ENABLE_Z_B_SMALL` 宏控制；
- `ZOP_SH1ADD` 到 `ZOP_RORI` 的 op 定义；
- 10 条 Z_B_SMALL 指令的 decode 条件；
- `z_b_small_op_is_small`；
- two-cycle 的 start / pending / stall 状态机；
- 保存 op / rd / rf_we / wb_sel / pc 的寄存器；
- 保存 rs1 / rs2 / compare flag / rotate partial 的寄存器；
- `z_b_small_final_result` 选择逻辑；
- pending 拍写入 EX2/MEM 的逻辑；
- `rori` 只使用 rs1 的 hazard 设置；
- `irom-z-b-small-test.coe`；
- `scripts/gen_irom_z_b_small_test.py`；
- Z_B_SMALL 相关 build 脚本，按同学工程路径调整。

不要这样移植：

- 不要直接用当前 `myCPU.sv` 覆盖同学的 317MHz `myCPU.sv`；
- 不要覆盖同学已经过 317MHz 的 forwarding/load/branch/PC 时序结构；
- 不要覆盖同学的 M 扩展优化；
- 不要覆盖同学已经验证过的 clock/reset/project 配置。

推荐做法：

只把 Z_B_SMALL decode + two-cycle pending/writeback 这一小块“挖出来”，嵌入同学 317MHz CPU，然后按同学 CPU 的 stall/hazard 网络做局部接线。

## 9. 移植风险点

- `stall_z_b_small` 可能和同学 CPU 的 stall 网络冲突。
- pending 拍写 EX2/MEM 的优先级可能放错。
- `rori` 可能被误判为使用 `rs2`，导致假的 load-use stall。
- Z_B_SMALL 后一条立即使用 rd 时，forwarding 时序可能和同学 CPU 不一致。
- `ENABLE_Z_B_SMALL` 可能被误开到官方 withMext-v2 构建里。
- active IROM 可能忘了从 `irom-z-b-small-test.coe` 切回 `withMext-v2`。
- 同步 `IROM_BRAM` 可能被覆盖回异步 `IROM(a/spo)`。
- 整文件覆盖会悄悄抹掉同学 317MHz 的关键 timing 优化。

## 10. 最小 diff 摘要

| 文件 | 改动类型 | 是否必须移植 | 说明 |
|---|---|---:|---|
| `digital_twin.srcs/sources_1/new/myCPU.sv` | Z_B_SMALL two-cycle RTL | 是，但只能局部移植 | 移植 Z_B_SMALL 小块和 hazard/stall 接口，不要整文件覆盖 |
| `digital_twin.srcs/sources_1/imports/test_src/irom-z-b-small-test.coe` | 测试 IROM | 是 | 最终期望 `LED=0x000003FF`，`SEG=0000000A` |
| `scripts/gen_irom_z_b_small_test.py` | 测试 IROM 生成脚本 | 是 | 包含依赖测试和 x0 测试 |
| `build_z_b_small_two_cycle_test_*.tcl` | 构建脚本 | 建议移植 | 路径和频率按同学工程调整 |
| `build_withmext_v2_283m_after_z_two_cycle.tcl` | 官方回归脚本 | 可参考 | 用于确认 Z 关闭时官方 IROM 仍然通过 |
| `mainline_virtual_platform_cdc.xdc` | 虚拟平台 CDC 约束 | 视情况 | 如果同学工程同样使用虚拟平台 top，可以保留；它不是 Z 逻辑 |
| `student_top.sv` | 同步 IROM_BRAM 修复 | 如果目标工程缺这个，就必须保留 | 不要退回异步 IROM |
| `perip_bridge.sv` / `dram_driver.sv` | 300MHz 整合中的写 strobe 路径 | Z-only 移植不需要 | 属于另一个提频方向 |
| `top.sv` / `digital_twin.xpr` / `pll.xci` | 300MHz 工程整合 | Z-only 移植不需要 | 优先保留同学 317MHz 已成功配置 |
