# Z_B_SMALL_IMPLEMENT_REPORT

## Summary

- Stable baseline kept: synchronous `IROM_BRAM` instruction fetch is unchanged.
- HDMI/UART/peripheral MMIO addresses were not changed.
- `ENABLE_Z_B_SMALL` is the gate for the second Z group. Default mainline build has no define, so this group is off by default.
- 200MHz Z_B_SMALL test bit was generated successfully.
- 200MHz Z_B_SMALL board test passed.
- 200MHz official withMext-v2 regression bit was generated successfully with `ENABLE_Z_B_SMALL` off.
- 283MHz was not run yet, because the requested order is to run it only after the 200MHz Z_B_SMALL functional board test passes.

## Files

RTL support is in the existing Z_LIGHT path:

- `digital_twin.srcs/sources_1/new/z_light_decode.sv`
- `digital_twin.srcs/sources_1/imports/new/z_light_unit.sv`
- `digital_twin.srcs/sources_1/new/myCPU.sv` reuses the existing `WB_SRC_Z` path.

New/generated test support:

- `scripts/gen_irom_z_b_small_test.py`
- `digital_twin.srcs/sources_1/imports/test_src/irom-z-b-small-test.coe`
- `build_z_b_small_test_200m.tcl`
- `Z_B_SMALL_IMPLEMENT_REPORT.md`

## Decode

All new instructions are disabled unless `ENABLE_Z_B_SMALL` is defined.

| Instruction | Opcode | funct7 | funct3 | Source usage |
|---|---:|---:|---:|---|
| `sh1add` | `0110011` | `0010000` | `010` | rs1 + rs2 |
| `sh2add` | `0110011` | `0010000` | `100` | rs1 + rs2 |
| `sh3add` | `0110011` | `0010000` | `110` | rs1 + rs2 |
| `min` | `0110011` | `0000101` | `100` | rs1 + rs2 |
| `minu` | `0110011` | `0000101` | `101` | rs1 + rs2 |
| `max` | `0110011` | `0000101` | `110` | rs1 + rs2 |
| `maxu` | `0110011` | `0000101` | `111` | rs1 + rs2 |
| `rol` | `0110011` | `0110000` | `001` | rs1 + rs2 |
| `ror` | `0110011` | `0110000` | `101` | rs1 + rs2 |
| `rori` | `0010011` | `0110000` | `101` | rs1 only, `instr[24:20]` shamt |

`rori` is decoded by full `funct7/funct3` under `OPIMM`, so it does not alias the existing `rev8`, `orc.b`, `brev8`, bit-immediate, `zip`, or `unzip` decodes.

## Execute Logic

| Instruction | EX result |
|---|---|
| `sh1add` | `(rs1 << 1) + rs2` |
| `sh2add` | `(rs1 << 2) + rs2` |
| `sh3add` | `(rs1 << 3) + rs2` |
| `min` | signed min |
| `minu` | unsigned min |
| `max` | signed max |
| `maxu` | unsigned max |
| `rol` | rotate-left by `rs2[4:0]` |
| `ror` | rotate-right by `rs2[4:0]` |
| `rori` | rotate-right by `instr[24:20]` |

The implementation remains single-cycle combinational logic in the Z unit. No new pipeline stage and no new multi-cycle stall were added.

## Hazard / Forwarding

- R-type Z_B_SMALL instructions use opcode `OP`, so the existing hazard logic treats them as using both `rs1` and `rs2`.
- `rori` uses opcode `OPIMM`, so the existing hazard logic treats it as using `rs1` only and does not create a false `rs2` load-use hazard.
- The existing `WB_SRC_Z` writeback path is reused, so EX/MEM and MEM/WB forwarding behavior follows the same Z_LIGHT path.
- Writes to `x0` remain disabled through the existing `id_rf_we = (id_rd != 5'd0)` gate.

## Test IROM

- Path: `digital_twin.srcs/sources_1/imports/test_src/irom-z-b-small-test.coe`
- SHA256: `C7D0DA75091A88ADC5E1322B71D9B233B0B16F578E7F64884C81864572C95AB9`
- Generator: `scripts/gen_irom_z_b_small_test.py`

Expected pass result on board:

- `LED = 0x000003FF`
- `SEG = 0x0000000A`

Failure behavior:

- `SEG = 0xBAD000xx`, where `xx` is the failing test index.
- LED keeps the pass bits already completed before the failure.

Test cases:

| bit | Instruction | Inputs | Expected |
|---:|---|---|---|
| 0 | `sh1add` | `rs1=3, rs2=5` | `11` |
| 1 | `sh2add` | `rs1=3, rs2=5` | `17` |
| 2 | `sh3add` | `rs1=3, rs2=5` | `29` |
| 3 | `min` | `rs1=0xffffffff, rs2=1` | `0xffffffff` |
| 4 | `minu` | `rs1=0xffffffff, rs2=1` | `1` |
| 5 | `max` | `rs1=0xffffffff, rs2=1` | `1` |
| 6 | `maxu` | `rs1=0xffffffff, rs2=1` | `0xffffffff` |
| 7 | `rol` | `rs1=0x80000001, rs2=1` | `0x00000003` |
| 8 | `ror` | `rs1=0x80000001, rs2=1` | `0xc0000000` |
| 9 | `rori` | `rs1=0x80000001, shamt=1` | `0xc0000000` |

## 200MHz Z_B_SMALL Test Build

- Script: `build_z_b_small_test_200m.tcl`
- `verilog_define`: `ENABLE_Z_B_SMALL`
- Bit: `final_bits/Z_B_SMALL_TEST_200MHz_20260714_160936.bit`
- Root copy: `Z_B_SMALL_TEST_200MHz.bit`
- Bit SHA256: `007FF9BEA8F79EF252C1B14D418CCEB5A7D6EDC840A92739727701B2D31F615A`
- WNS/TNS/WHS: `0.270 / 0.000 / 0.092`
- DRC errors: `0`
- BIVC/NSTD/UCIO: `0 / 0 / 0`
- IROM/IP refresh: `IROM=1`, `IROM_BRAM=1`, `DRAM=1`, `PLL=1`
- Resume/open_checkpoint: `0 / 0`
- Board result: pass
- Board LED: `0x000003FF`
- Board SEG: `0000000A`
- Conclusion: all 10 Z_B_SMALL instructions passed at 200MHz.

## 200MHz withMext-v2 Regression

- Script: `build_ip_restored_200m_withMext_v2.tcl`
- `ENABLE_Z_B_SMALL`: off, `verilog_define` empty
- Bit: `final_bits/IP_RESTORED_withMext_v2_200MHz_20260714_161533.bit`
- Root copy: `IP_RESTORED_withMext_v2_200MHz.bit`
- Bit SHA256: `2A084AE8B66E84708B4CC00D716C249414A0BBFF9669B5DAAF56011DB753B334`
- IROM SHA256: `0CEA80F2CA36E2672AC8D1E3D0087F88DC24B5A33A177C74B47330B0637C6A1B`
- DRAM SHA256: `D1C6D8F4ADBE80D618CCFCCC0336A9A61B56007B0F44A4E79BDDF71CCAB89C03`
- WNS/TNS/WHS: `0.452 / 0.000 / 0.055`
- DRC errors: `0`

## Notes

- `myCPU.sv`: not edited for this report; existing Z path was reused.
- `student_top.sv`: not edited; synchronous `IROM_BRAM` fix is preserved.
- `perip_bridge.sv`: not edited; MMIO addresses are unchanged.
- `withMext-v2` active IROM/DRAM were restored by the regression build after generating the Z_B_SMALL test bit.
- 283MHz Z_B_SMALL and 283MHz withMext-v2 builds are the next step after this 200MHz pass checkpoint.
