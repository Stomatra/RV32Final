这个报告已经把问题定位得很清楚了：**现在真正拖时序的不是 `memwb_wdata` 数据本身，而是 `memwb_rf_we / memwb_can_forward` 这类控制命中线扇出太大，并且污染到了 PC 和 ID/EX 两条反馈路径。**

所以乘法器先放一边是对的。乘法器优化解决不了这个：

```text id="wfatdd"
memwb_rf_we_reg/C -> pc_q_reg
memwb_rf_we_reg/C -> idex_rs1_val / idex_csr_wdata
```

这个问题要优先处理。

---

# 1. 当前报告说明了什么？

你现在的关键问题是：

```text id="bvd4jg"
WNS = -0.074 ns
TNS = -1.944 ns
Failing endpoints = 43
```

这已经不是单个边缘路径了，而是一组由同一个源头扩散出来的路径：

```text id="a92uhk"
source = memwb_rf_we_reg/C
```

也就是说：

```text id="a6uk4b"
memwb_rf_we 这个控制信号被同时拿去做：
1. PC 前递判断
2. branch/jalr 操作数选择
3. PC redirect
4. PC CE
5. ID 阶段同周期旁路
6. CSR 写数据旁路
```

所以它的 route delay 很大：

```text id="pljmz8"
route delay 大约 4ns
logic delay 只有 0.8ns 左右
```

这说明问题主要是**扇出和布局布线距离**，不是逻辑本身特别复杂。

---

# 2. 方案 B 是正确方向，但要注意一个坑

Codex 推荐的方案 B：

```text id="uufvy8"
增加 branch/jalr 对 MEM/WB 依赖时的额外 stall，
然后取消 MEM/WB -> PC 前递。
```

大方向是对的。

但是要注意：如果你直接写一个组合逻辑：

```systemverilog id="w9yg5m"
assign pc_wb_hazard =
    ifid_valid &&
    id_is_branch_or_jalr &&
    memwb_rf_we &&
    memwb_rd != 5'd0 &&
    ...
```

然后把它接到 PC hold / IFID hold / ID/EX bubble，那么你仍然会产生一条路径：

```text id="s2o99d"
memwb_rf_we_reg -> pc_q_reg[CE]
```

也就是说，虽然你砍掉了：

```text id="4cygso"
MEM/WB -> PC D
```

但可能还留下：

```text id="pg08l1"
MEM/WB -> PC CE
```

而你的报告里 PC CE 本来就是负 slack 路径之一。

所以真正想把 `MEM/WB -> PC` 时序砍掉，最好不要让 `memwb_rf_we` 当周期直接控制 PC。

---

# 3. 更推荐的做法：用“上一拍检测，下一拍注册 stall”

也就是不要在 MEM/WB 当周期才发现 hazard，而是在它还处于 EX/MEM 或 MEM 阶段时就提前发现，然后打一拍寄存器，下一拍用这个寄存器去 hold PC。

思路如下：

```text id="rmpxy0"
当前周期：
    branch/jalr 在 IF/ID
    相关生产者在 EX/MEM 或 MEM 阶段
    检测到 pc_mem_hazard

下一周期：
    生产者进入 MEM/WB 写回
    使用 pc_wait_wb_q 这个寄存器信号 hold PC/IFID
    不再需要 memwb_rf_we 直接控制 PC

再下一周期：
    RF 已经写回
    branch/jalr 进入 ID/EX
    EX 阶段不再需要 MEM/WB -> PC 前递
```

这样可以把原来的长路径：

```text id="t3my5g"
memwb_rf_we -> pc_q
```

换成：

```text id="l4f62l"
pc_wait_wb_q_reg -> pc_q
```

这个 `pc_wait_wb_q` 是本地寄存器，通常好布线得多。

---

# 4. 结构上可以这样改

## 第一步：保留普通 ALU 的 MEM/WB 前递

这些不要动：

```systemverilog id="osoz7f"
ex_fwd_rs1_from_memwb
ex_fwd_rs2_from_memwb
```

普通 ALU 指令仍然需要 MEM/WB 前递。

---

## 第二步：取消 PC 专用 MEM/WB 前递

也就是把这两个关掉：

```systemverilog id="zwj0u2"
assign ex_pc_fwd_rs1_from_memwb = 1'b0;
assign ex_pc_fwd_rs2_from_memwb = 1'b0;
```

或者从 `ex_pc_rs1_val / ex_pc_rs2_val` 的 mux 里移除 `memwb_wdata` 这一支。

目的就是砍掉：

```text id="3n5190"
memwb_rf_we -> ex_pc_rs*_val -> branch/jalr -> pc_next
```

---

## 第三步：新增一个注册化的 WB 等待信号

伪代码大概是这样：

```systemverilog id="f59m02"
logic pc_wait_wb_q;

always_ff @(posedge cpu_clk or posedge cpu_rst) begin
    if (cpu_rst) begin
        pc_wait_wb_q <= 1'b0;
    end else if (ex_redirect_flush) begin
        pc_wait_wb_q <= 1'b0;
    end else begin
        pc_wait_wb_q <= pc_mem_hazard;
    end
end
```

这里的 `pc_mem_hazard` 指的是：

```text id="dvxwyh"
branch/jalr 在 IF/ID，
且它依赖的 rd 当前在 EX/MEM 或 MEM 阶段，
下一拍可能进入 MEM/WB。
```

然后 stall 条件里加入：

```systemverilog id="xrgc9v"
assign pc_feedback_stall =
    pc_ex_hazard |
    pc_mem_hazard |
    pc_wait_wb_q;
```

再把它接到：

```text id="pp4z1f"
PC hold
IF/ID hold
ID/EX bubble
```

注意，这里不要再用组合的 `pc_wb_hazard = memwb_rf_we && ...` 去直接控制 PC，否则 `memwb_rf_we -> PC CE` 还是会存在。

---

# 5. 这能不能覆盖之前的 `lw -> bne` bug？

可以，但前提是 stall 流程正确。

之前 bug 是：

```asm id="b19id3"
lw  x15, ...
bne x15, x0, ...
```

原来只 stall 到 load 进入 MEM/WB，然后 branch 在 EX 需要通过 MEM/WB -> PC 前递拿值。

现在改成：

```text id="ms3m0w"
load 还没写回时，branch 一直留在 IF/ID
load 进入 MEM/WB 写回那一拍，再用 pc_wait_wb_q 多 hold 一拍
下一拍 branch 重新读 RF，此时 x15 已经是新值
branch 进入 ID/EX
EX 阶段直接用 idex_rs1_val，不需要 MEM/WB -> PC 前递
```

所以功能上是成立的。

代价是：

```text id="h02n6d"
branch/jalr 依赖前面结果时，可能多 stall 1 拍
```

但是换来的好处是：

```text id="y4z4xe"
PC 关键反馈路径大幅缩短
```

这个 trade-off 值得。

---

# 6. ID/EX 那条路径先不要急着删

报告里还有：

```text id="kzfyf4"
memwb_rf_we_reg -> idex_rs1_val_reg
memwb_rf_we_reg -> idex_csr_wdata_reg
```

这是 ID 阶段同周期写回旁路。

这条路径也有轻微负 slack：

```text id="tiz0zv"
-0.038 ns
-0.019 ns
```

但是我建议先不要同时删它。

原因是：这个旁路用于处理这种情况：

```text id="i7iut4"
上一条结果正在 WB 写回
当前指令正在 ID 阶段准备进入 ID/EX
```

如果没有旁路，ID/EX 可能在同一个时钟沿捕获到旧 RF 值。

虽然 RF 是同步写、组合读，但 ID/EX 寄存器也是同一个时钟沿采样，不能简单认为“写回后一整拍 ID 可读到新值”就能覆盖同边沿捕获问题。

所以建议分两步：

```text id="9n0qmp"
第一步：先砍 MEM/WB -> PC
第二步：重新跑 timing
第三步：如果 WNS 仍然卡在 MEM/WB -> ID/EX，再单独处理 ID bypass
```

不要一次同时改 PC 前递和 ID 旁路，否则功能问题不好定位。

---

# 7. 对 ID/EX 旁路的后续优化方向

如果 PC 路径砍掉后，新的 WNS 变成：

```text id="lfs5xk"
memwb_rf_we_reg -> idex_rs1_val_reg
memwb_rf_we_reg -> idex_csr_wdata_reg
```

那再考虑：

## 方案 1：拆分 ID 旁路控制线

把共享的：

```systemverilog id="s5y00a"
memwb_can_forward
```

拆成：

```systemverilog id="m29eo4"
memwb_can_forward_id
memwb_can_forward_ex
memwb_can_forward_pc
```

甚至单独复制：

```systemverilog id="bntc3l"
(* max_fanout = 16 *) wire memwb_rf_we_id = memwb_rf_we;
(* max_fanout = 16 *) wire memwb_rf_we_ex = memwb_rf_we;
```

让 Vivado 有机会复制和就近放置。

---

## 方案 2：只对真正使用 rs1/rs2 的指令做比较

比如：

```systemverilog id="ly7dsv"
id_rs1_bypass =
    ifid_valid &&
    id_uses_rs1 &&
    memwb_rf_we_id &&
    memwb_rd != 5'd0 &&
    memwb_rd == ifid_rs1;
```

不要让 CSR、branch、ALU、store 全部共享同一条大比较链。

---

## 方案 3：如果还不过，再考虑 ID 也额外 stall

这是最稳但最损性能的方案：

```text id="c9ptba"
当 IF/ID 指令依赖 MEM/WB 写回时，
多 hold 一拍，
等 RF 写回后下一拍再进入 ID/EX。
```

这样可以删除 ID 同周期旁路，但 CPI 会增加。

建议作为最后手段。

---

# 8. 给 Codex 的下一条可以这样发

```text id="e2o36x"
当前 timing report 已确认 source 主要是 memwb_rf_we_reg/C，关键问题是 MEM/WB feedback 控制线扇出太大。先不要动乘法器，也不要动普通 ALU 的 MEM/WB 前递。

请优先实现“注册化 WB 等待”的方案，目标是取消 MEM/WB -> PC 的组合前递，同时避免 memwb_rf_we 当周期直接控制 PC CE。

要求：

1. 保留普通 ALU 的 ex_fwd_rs1_from_memwb / ex_fwd_rs2_from_memwb。
2. 取消 PC 专用 MEM/WB 前递：
   ex_pc_fwd_rs1_from_memwb = 1'b0;
   ex_pc_fwd_rs2_from_memwb = 1'b0;
   或从 ex_pc_rs1_val / ex_pc_rs2_val mux 中移除 memwb_wdata 分支。

3. 不要使用组合 pc_wb_hazard = memwb_rf_we && ... 直接控制 PC hold，因为这会继续产生 memwb_rf_we_reg -> pc_q_reg[CE] 路径。

4. 使用上一拍的 pc_mem_hazard 生成注册信号 pc_wait_wb_q：
   - 当 branch/jalr 在 IF/ID，且依赖的生产者在 EX/MEM 或 MEM 阶段时，当前周期已有 pc_mem_hazard hold。
   - 同时把 pc_mem_hazard 打一拍为 pc_wait_wb_q。
   - 下一拍生产者进入 MEM/WB 时，用 pc_wait_wb_q 再 hold PC/IFID 一拍。
   - 再下一拍 RF 已写回，branch/jalr 进入 ID/EX，不再需要 MEM/WB -> PC 前递。

5. 把 pc_wait_wb_q 加入 PC hold、IF/ID hold、ID/EX bubble，与 pc_ex_hazard/pc_mem_hazard 同类处理。

6. 保留 ID 阶段 MEM/WB 同周期旁路，暂时不要删 id_rs1_val/id_rs2_val/id_csr_wdata 的 MEM/WB bypass。

7. 修改后跑：
   - lw -> bne 单测
   - jalr 依赖前一条写回的单测
   - CSR/trap 官方测试
   - 完整官方程序

8. 重新生成 routed timing report，重点确认：
   - 是否还存在 memwb_rf_we_reg -> pc_q_reg 的负 slack；
   - 新的 WNS/TNS/failing endpoints；
   - 如果新的最差路径变成 memwb_rf_we_reg -> idex_*，再单独处理 ID bypass。
```

---

# 9. 当前推荐结论

我建议你现在选这个策略：

```text id="uvp20q"
第一阶段：只砍 MEM/WB -> PC，不动 MEM/WB -> ID/EX。
```

具体是：

```text id="j0qffo"
取消 PC 专用 MEM/WB 前递；
增加注册化 pc_wait_wb_q；
用多 stall 一拍保证 branch/jalr 正确性。
```

这样最有希望直接消掉当前最严重的：

```text id="t98mbu"
memwb_rf_we_reg -> pc_q_reg
```

路径。

然后再看 ID/EX 是否成为新的瓶颈。
