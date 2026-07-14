# IP_RESTORE_200M_REPORT

- Shell source: official clean shell extracted into `E:/Projects/1Aprojects/RV32Final` before migration.
- Borrowed IP audit: `BORROWED_IP_AUDIT.md`
- Current IP audit before restore: `CURRENT_IP_AUDIT.md`
- Restored IP folders: `IROM_BRAM`, `IROM_BRAM_1` copied into `digital_twin.srcs/sources_1/ip` and `digital_twin.gen/sources_1/ip`.
- Note: `IROM_BRAM_1/IROM_BRAM.xci` has the same IP component name as `IROM_BRAM`, so only `IROM_BRAM/IROM_BRAM.xci` was added as a Vivado IP to avoid duplicate IP instance names.
- `student_top.sv` now instantiates synchronous `IROM_BRAM` instead of asynchronous `IROM`, matching the current `myCPU.sv` fetch pipeline comments/logic.
- Not migrated from old project: HDMI tops, UART echo/debug tops, `uart_rx.sv`, HDMI serializer/colorbar files, cpu_hdmi XDC files, smoke/echo/debug IROMs, old runs/cache/.Xil/checkpoints/build_outputs.
- top: `top`
- XDC list: `E:/Projects/1Aprojects/RV32Final/digital_twin.srcs/constrs_1/new/digital_twin.xdc`
- compile order: `E:/Projects/1Aprojects/RV32Final/ip_restore_build_outputs/compile_order_IP_RESTORED_withMext_v2_200MHz_20260714_153440.txt`
- get_ips: `DRAM IROM IROM_BRAM pll`
- IROM_BRAM recognized by Vivado: `1`
- IROM_BRAM_1 recognized by Vivado: `0`
- IROM SHA256: `0CEA80F2CA36E2672AC8D1E3D0087F88DC24B5A33A177C74B47330B0637C6A1B`
- DRAM SHA256: `D1C6D8F4ADBE80D618CCFCCC0336A9A61B56007B0F44A4E79BDDF71CCAB89C03`
- IROM_BRAM.xci SHA256: `DC50F4C52A3F19B57D38192A9176FE9A323BBD41D6B5C583D00DFCFB5AD980DF`
- IROM_BRAM.mif SHA256: `3476CDF70062328F8C3BCFA4A4FD5A2FD3F7632D3F2BBF8234B4160923C4C753`
- IROM_BRAM_1/IROM_BRAM.xci SHA256: `C4C0BA17693C55E7E64F146BAADB0A4316CE4F7002C95494BA273CB96501DBFC`
- dram_driver sync: `1 words=14 mismatches=0`
- dram_driver.sv SHA256: `3F6D6F5FF7F391C263621B55D2A90AAB8F270422B6D65EE779E4541CF18CB8FB`
- myCPU.sv SHA256: `20E20B541B3062EC056E98ED9F4CFC4FA4DE8DE0B53D24DB4F77E34FEA24071E`
- perip_bridge.sv SHA256: `D279FB1A6E2777D9662A949B5C72AC9F14D1E5C889C2470CBB83FF85E4E70FF8`
- pll.xci SHA256: `D6CFDBA15073C2CBA9AC0FF17D0731164D503DAA7265A0D7D93AA4D9A3DD02B1`
- digital_twin.xdc SHA256: `BD2954050BDB99860ED35DBAA65545E4BAC5FA92C08EC45DB6C498C3114DBEF1`
- report_clocks clk_out2_pll period/freq: `5.000 ns / 200.000 MHz`
- WNS/TNS/WHS: `0.293 / 0.000 / 0.078`
- DRC errors: `0`
- BIVC/NSTD/UCIO: `0 / 0 / 0`
- bit path: `E:/Projects/1Aprojects/RV32Final/final_bits/IP_RESTORED_withMext_v2_200MHz_20260714_153440.bit`
- root bit path: `E:/Projects/1Aprojects/RV32Final/IP_RESTORED_withMext_v2_200MHz.bit`
- bit SHA256: `6B96B3A1E99A5F525960E81FDA0EFFD2E4854FE9FEA5CDCD060EB968DB1BAA57`
- timing report: `E:/Projects/1Aprojects/RV32Final/ip_restore_build_outputs/timing_IP_RESTORED_withMext_v2_200MHz_20260714_153440.rpt`
- DRC report: `E:/Projects/1Aprojects/RV32Final/ip_restore_build_outputs/drc_IP_RESTORED_withMext_v2_200MHz_20260714_153440.rpt`

## IROM Relationship Audit

- `student_top.sv` originally instantiated `IROM Mem_IROM(.a(inst_addr), .spo(instruction))`.
- The current generated `IROM` IP is `dist_mem_gen`, interface `a/spo`, no clock.
- The current `myCPU.sv` fetch stage records `fetch_pc_q` for a synchronous BRAM return path and comments explicitly refer to BRAM returning data on the next cycle.
- Borrowed `IROM_BRAM` is `blk_mem_gen`, interface `clka/ena/addra/douta`, read latency 1.
- Therefore, simply copying `IROM_BRAM` folders without changing `student_top.sv` would not affect instruction fetch, because no source referenced `IROM_BRAM`.
- Minimal source change made: `student_top.sv` now instantiates `IROM_BRAM` with `clka=w_cpu_clk`, `ena=1'b1`, `addra=inst_addr`, `douta=instruction`.

## IP Restore Notes

- Backup created before IP restore: `backup_before_ip_restore_20260714/`.
- Copied from `E:/ip/ip`:
  - `IROM_BRAM` to `digital_twin.srcs/sources_1/ip/IROM_BRAM` and `digital_twin.gen/sources_1/ip/IROM_BRAM`
  - `IROM_BRAM_1` to `digital_twin.srcs/sources_1/ip/IROM_BRAM_1` and `digital_twin.gen/sources_1/ip/IROM_BRAM_1`
- `IROM_BRAM_1` contains an `IROM_BRAM.xci` whose IP component name is also `IROM_BRAM`; it was not added as a second Vivado IP to avoid duplicate IP instance names.
- Borrowed `pll_1/pll.xci` requested 285 MHz, so it was not used for this 200 MHz validation. Current `pll_1` remained active and was configured to 200 MHz by the build script.
- `IROM_BRAM.mif` SHA256 matches current generated `IROM.mif`: `3476CDF70062328F8C3BCFA4A4FD5A2FD3F7632D3F2BBF8234B4160923C4C753`.
- `IROM_BRAM_synth_1` completed successfully and generated `digital_twin.runs/IROM_BRAM_synth_1/IROM_BRAM.dcp`.
- `compile_order` does not list the `.xci` directly because the IP is handled as an out-of-context IP; `get_ips` is the authoritative check here.

## Board Expectation

Burn `IP_RESTORED_withMext_v2_200MHz.bit`.

Expected result:

- left check mark on
- official 8 lights on
- SEG similar to `378xxxxx`
