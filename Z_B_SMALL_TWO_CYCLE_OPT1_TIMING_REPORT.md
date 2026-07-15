# Z_B_SMALL Two-Cycle OPT1 Timing Report

## Summary

- Goal: remove the EX1/EX2 Q-to-D feedback mux from the Z_B_SMALL two-cycle hold path and recheck timing.
- Status:
  - Official `withMext-v2` regression at 283.333MHz passes timing with `ENABLE_Z_B_SMALL` off.
  - `Z_B_SMALL_TWO_CYCLE_TEST` at 283.333MHz passes timing with `ENABLE_Z_B_SMALL` on.
  - `Z_B_SMALL_TWO_CYCLE_TEST` at 300.000MHz still fails timing, now on the DRAM read/perip return path rather than rotate or EX1/EX2 hold.
- No tag was created. Board validation is still pending for the 200MHz two-cycle bit and the new 283.333MHz OPT1 bit.

## RTL Change

- File: `digital_twin.srcs/sources_1/new/myCPU.sv`
- `ENABLE_Z_B_SMALL` mode now lets EX1/EX2 operand registers infer clock-enable style hold instead of forcing wide data feedback muxes.
- Mainline mode keeps the proven `(* extract_enable = "no" *)` shape for the same EX1/EX2 data registers when `ENABLE_Z_B_SMALL` is off.
- `hold_ex1ex2 = mem_load_stall || m_stall || stall_z_b_small` is used as an FF hold branch, not as a combinational data feedback assignment.
- The Z_B_SMALL two-cycle pending path still inserts a bubble on the start cycle and emits the saved result on the pending cycle.

Relevant code locations:

- `myCPU.sv:299`: conditional EX1/EX2 register declarations for Z_B_SMALL versus mainline.
- `myCPU.sv:720`: `z_b_small_start` / `stall_z_b_small` / `hold_ex1ex2` generation.
- `myCPU.sv:1731`: EX1/EX2 pipeline register hold uses FF hold branch.
- `myCPU.sv:1879`: Z_B_SMALL pending register capture.
- `myCPU.sv:1945`: EX2/MEM bubble insertion on Z_B_SMALL start cycle.

No changes were made to M extension logic, IROM_BRAM, perip_bridge address map, rotate logic, false paths, or multicycle constraints.

## Official withMext-v2 Regression

- Build: `WITHMEXT_V2_283MHz_AFTER_Z_TWO_CYCLE`
- Bit: `final_bits/WITHMEXT_V2_283MHz_AFTER_Z_TWO_CYCLE_20260715_091114.bit`
- Root bit: `WITHMEXT_V2_283MHz_AFTER_Z_TWO_CYCLE.bit`
- Bit SHA256: `51A34ED9CF9AF074C24C634888C43A85A75A686BDA7FE8EB955DC59DCB3F14C5`
- IROM SHA256: `0CEA80F2CA36E2672AC8D1E3D0087F88DC24B5A33A177C74B47330B0637C6A1B`
- DRAM SHA256: `D1C6D8F4ADBE80D618CCFCCC0336A9A61B56007B0F44A4E79BDDF71CCAB89C03`
- IROM_BRAM.mif SHA256: `3476CDF70062328F8C3BCFA4A4FD5A2FD3F7632D3F2BBF8234B4160923C4C753`
- CPU clock: `283.333MHz`, period `3.529ns`
- `ENABLE_Z_B_SMALL`: off
- XDC: `digital_twin.xdc` + `mainline_virtual_platform_cdc.xdc`
- WNS/TNS/WHS: `+0.002 / 0.000 / +0.085`
- DRC errors: `0`
- Worst source: `student_top_inst/Core_cpu/ex1ex2_rs1_val_reg[2]/C`
- Worst destination: `student_top_inst/Core_cpu/fetch_hold_instr_reg[8]/CE`
- Worst path logic/route delay: `0.900ns / 2.307ns`
- Board expectation: left check, 8 official lights on, `SEG=378xxxxx`
- Board result: pending.

## Z_B_SMALL 283.333MHz OPT1

- Build: `Z_B_SMALL_TWO_CYCLE_TEST_283MHz_OPT1`
- Bit: `final_bits/Z_B_SMALL_TWO_CYCLE_TEST_283MHz_OPT1_20260715_092856.bit`
- Root bit: `Z_B_SMALL_TWO_CYCLE_TEST_283MHz_OPT1.bit`
- Bit SHA256: `B444CAABA48B745443C6913BF0752F2FA9FFF9AC93E756AA9F8B3EA9E343FE49`
- IROM SHA256: `D5A762CA186A770E300E3E3B0940B0A6333FB6074F43653EC3361019461B9FFE`
- DRAM SHA256: `D1C6D8F4ADBE80D618CCFCCC0336A9A61B56007B0F44A4E79BDDF71CCAB89C03`
- IROM_BRAM.mif SHA256: `3476CDF70062328F8C3BCFA4A4FD5A2FD3F7632D3F2BBF8234B4160923C4C753`
- CPU clock: `283.333MHz`, period `3.529ns`
- `ENABLE_Z_B_SMALL`: on
- XDC: `digital_twin.xdc` + `mainline_virtual_platform_cdc.xdc`
- WNS/TNS/WHS: `+0.025 / 0.000 / +0.023`
- DRC errors: `0`
- Worst source: `student_top_inst/Core_cpu/ex2mem_alu_y_reg[4]_rep/C`
- Worst destination: `student_top_inst/bridge_inst/dram_driver_inst/dram_lane0_reg_0_1/ADDRARDADDR[2]`
- Worst path logic/route delay: `0.223ns / 2.691ns`
- Result: timing passes. The previous `ex1ex2_alu_b_reg -> ex1ex2_rs1_val_reg` hold path is no longer the worst path.
- Board expectation: `LED=0x000003FF`, `SEG=0000000A`
- Board result: pending.

## Z_B_SMALL 300.000MHz OPT1

- Build: `Z_B_SMALL_TWO_CYCLE_TEST_300MHz_OPT1`
- Bit: `final_bits/Z_B_SMALL_TWO_CYCLE_TEST_300MHz_OPT1_20260715_094501.bit`
- Root bit: `Z_B_SMALL_TWO_CYCLE_TEST_300MHz_OPT1.bit`
- Bit SHA256: `7E039CF911B1E43923903F90A8BA3316295AFF65229088BFD16BCE835E11CFC0`
- IROM SHA256: `D5A762CA186A770E300E3E3B0940B0A6333FB6074F43653EC3361019461B9FFE`
- DRAM SHA256: `D1C6D8F4ADBE80D618CCFCCC0336A9A61B56007B0F44A4E79BDDF71CCAB89C03`
- IROM_BRAM.mif SHA256: `3476CDF70062328F8C3BCFA4A4FD5A2FD3F2BBF8234B4160923C4C753`
- CPU clock: `300.000MHz`, period `3.333ns`
- `ENABLE_Z_B_SMALL`: on
- XDC: `digital_twin.xdc` + `mainline_virtual_platform_cdc.xdc`
- WNS/TNS/WHS: `-0.356 / -154.553 / +0.084`
- DRC errors: `0`
- Worst source: `student_top_inst/bridge_inst/dram_driver_inst/dram_lane3_reg_0_2/CLKARDCLK`
- Worst destination: `student_top_inst/bridge_inst/perip_rdata_q_reg[26]/D`
- Worst path logic/route delay: `2.485ns / 1.042ns`
- Result: timing fails. The failing path is now the DRAM/perip read-data return path, not rotate, Z result mux, or EX1/EX2 hold feedback.

## Interpretation

- The OPT1 register-shape change fixed the immediate EX1/EX2 hold bottleneck at 283.333MHz.
- Z_B_SMALL at 283.333MHz now has positive slack and is ready for board validation.
- 300MHz is not closed by this change; the next bottleneck is outside the Z_B_SMALL rotate/result path.
- Official withMext-v2 remains timing-clean at 283.333MHz with `ENABLE_Z_B_SMALL` off, so the conditional register-shape change did not regress the mainline timing path.

## Next Step

- Board-test `Z_B_SMALL_TWO_CYCLE_TEST_283MHz_OPT1.bit`.
- If it shows `LED=0x000003FF` and `SEG=0000000A`, and the official withMext-v2 regression bit also boards correctly, then it is reasonable to tag the 283.333MHz Z_B_SMALL pass.
- Do not tag the 300MHz bit; it fails timing.
