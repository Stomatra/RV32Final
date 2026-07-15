# Z_B_SMALL_TWO_CYCLE_REPORT

## Summary

- Goal: make the second Z_B_SMALL set execute in two cycles instead of one long EX2 combinational path.
- Status: 200MHz build passes timing and bitgen. 283.333MHz build is a near miss with WNS = -0.015ns, so 300MHz was not run.
- No tag was created.

## Modified Files

- `digital_twin.srcs/sources_1/new/myCPU.sv`
  - Adds the Z_B_SMALL pending register path.
  - Splits second-class Z operations into stage1 capture and stage2 final result.
  - Inserts one bubble into EX2/MEM on the start cycle.
  - Stalls PC, IF/ID, ID/EX1, and EX1/EX2 for exactly the start cycle.
- `scripts/gen_irom_z_b_small_test.py`
  - Regenerates `irom-z-b-small-test.coe`.
  - Adds immediate dependent-use tests for `sh1add`, `ror`, and `rori`.
  - Adds a branch dependent-use test.
  - Adds a write-to-x0 test.
- `digital_twin.srcs/sources_1/imports/test_src/irom-z-b-small-test.coe`
  - New SHA256: `D5A762CA186A770E300E3E3B0940B0A6333FB6074F43653EC3361019461B9FFE`
- `build_z_b_small_two_cycle_test_200m.tcl`
- `build_z_b_small_two_cycle_test_283m_cdc_cut.tcl`
- `build_z_b_small_two_cycle_test_300m_cdc_cut.tcl`

## Two-Cycle Design

- `z_b_small_start` fires when a valid enabled Z_B_SMALL op reaches EX2 and no pending op exists.
- Start cycle:
  - saves op, rd, rf_we, wb_sel, pc, rs1, rs2, high rotate shamt bits, and stage1 partial result;
  - inserts an EX2/MEM bubble;
  - asserts `stall_z_b_small` to hold the front end and EX1/EX2 for one cycle.
- Pending cycle:
  - computes final result from saved registers;
  - writes saved control and result into EX2/MEM;
  - releases the stall and clears pending.

## Stage Split

- `sh1add/sh2add/sh3add`: stage1 stores fixed-shifted rs1, stage2 adds saved rs2.
- `rol/ror/rori`: stage1 rotates by low shamt bits `[2:0]`, stage2 rotates by high bits `[4:3]`.
- `min/minu/max/maxu`: stage1 currently saves operands and compare flags, stage2 selects saved rs1/rs2.
- Existing simple Z_LIGHT instructions still use the old single-cycle Z path.

## Hazard And Forwarding

- R-type Z_B_SMALL still decodes as using rs1 and rs2.
- `rori` decodes as using rs1 only, so it does not create a false rs2 load-use hazard.
- The one-cycle stall lets the following instruction use the result through the existing EX2/MEM or MEM/WB forwarding path.
- Extra IROM checks now cover immediate add-use, immediate branch-use, and x0 write suppression.

## 200MHz Build

- Bit: `final_bits/Z_B_SMALL_TWO_CYCLE_TEST_200MHz_20260714_204301.bit`
- Root bit: `Z_B_SMALL_TWO_CYCLE_TEST_200MHz.bit`
- Bit SHA256: `20456CC3DF0F80958FE28928F219F3FC72745D83F1A485636985FA0F319C7056`
- IROM SHA256: `D5A762CA186A770E300E3E3B0940B0A6333FB6074F43653EC3361019461B9FFE`
- WNS/TNS/WHS: `+0.156 / 0.000 / +0.074`
- DRC errors: `0`
- Board expectation: `LED=0x000003FF`, `SEG=0000000A`
- Board result: pending user test.

## 283.333MHz Build

- Bit: `final_bits/Z_B_SMALL_TWO_CYCLE_TEST_283MHz_20260714_213113.bit`
- Root bit: `Z_B_SMALL_TWO_CYCLE_TEST_283MHz.bit`
- Bit SHA256: `54F1C27ED19EBB65E07DBBC94090FC93F8EAE35438A6ADE02AFD6AD9D243321C`
- CPU clock report: `283.333MHz`, period `3.529ns`
- WNS/TNS/WHS: `-0.015 / -0.025 / +0.085`
- DRC errors: `0`
- Worst source: `student_top_inst/Core_cpu/ex1ex2_alu_b_reg[0]/C`
- Worst destination: `student_top_inst/Core_cpu/ex1ex2_rs1_val_reg[0]/D`
- Worst path logic/route: `1.443ns / 1.975ns`
- Result: timing failed by 15ps, so this bit is not tagged as good.

## Worst Path Comparison

- Before two-cycle: Z_B_SMALL result path, WNS about `-0.192ns`.
- After two-cycle: worst path moved away from rotate result logic.
- New worst path is EX1/EX2 forwarding/hold related, not the original `rol/ror/rori -> z_result -> wb_data` path.

## 300MHz

- Not run.
- Reason: 283.333MHz still has WNS < 0, so 300MHz would not be meaningful yet.

## Regression Notes

- `ENABLE_Z_B_SMALL` remains off by default.
- The Z_B_SMALL test scripts explicitly enable `ENABLE_Z_B_SMALL`.
- Synchronous `IROM_BRAM` fetch path is preserved.
- No CPU-internal false path or multicycle path was added for Z_B_SMALL.
- No changes were made to M extension, perip_bridge address map, HDMI, or UART.

## Suggested Next Step

- The next optimization target is not the rotate unit anymore.
- Focus on the EX1/EX2 same-cycle forwarding/hold path:
  - worst path touches `ex1ex2_alu_b`, `u_alu/adder_b`, and `ex1ex2_rs1_val` feedback/forwarding logic;
  - closing the remaining 15ps may be possible through a small forwarding timing cleanup or another implementation seed/strategy, but it should be treated separately from the Z_B_SMALL two-cycle split.
