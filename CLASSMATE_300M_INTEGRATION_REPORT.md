# Classmate 300MHz Integration Report

## Scope

Integrated the timing-oriented changes from:

`digital_twin.srcs/new1/new`

into the current baseline while preserving:

- synchronous `IROM_BRAM` instruction fetch
- existing M extension behavior
- existing Z_LIGHT support
- optional two-cycle `ENABLE_Z_B_SMALL` path
- current mainline top/project structure

The classmate files were not copied wholesale because their CPU sources do not
include the local `ENABLE_Z_B_SMALL` two-cycle implementation.

## Integrated Changes

### CPU datapath

File: `digital_twin.srcs/sources_1/new/myCPU.sv`

- Added `perip_wstrb[3:0]` output for DRAM byte-lane writes.
- Added DRAM region detection for `0x8010_0000` through `0x8013_FFFF`.
- Moved byte/half/word store data alignment into the CPU EX2/MEM path.
- Disabled same-cycle EX2 to EX1 forwarding and made adjacent RAW dependencies
  wait for the registered EX2/MEM forwarding path.
- Moved branch comparison to EX1 and registers the one-bit branch decision into
  EX1/EX2.
- Added one DSP input stage for M-extension multiply partial products.
- Kept the local two-cycle `ENABLE_Z_B_SMALL` path intact.

### DRAM write path

Files:

- `digital_twin.srcs/sources_1/new/perip_bridge.sv`
- `digital_twin.srcs/sources_1/new/dram_driver.sv`
- `digital_twin.srcs/sources_1/new/student_top.sv`

Changes:

- Added `perip_wstrb[3:0]` through `student_top` and `perip_bridge`.
- Replaced `dram_driver` internal `perip_mask`/address decode write mux with
  direct byte-lane write strobes from the CPU.
- Kept MMIO address decoding unchanged.

### Top-level CDC

Files:

- `digital_twin.srcs/sources_1/new/top.sv`
- `digital_twin.srcs/constrs_1/new/mainline_virtual_platform_cdc.xdc`
- `digital_twin.xpr`

Changes:

- Added two-flop synchronizers for virtual SW/KEY from 50 MHz twin-controller
  domain into the CPU domain.
- Added two-flop synchronizers for CPU LED/SEG status back into the 50 MHz
  twin-controller domain.
- Updated CDC exceptions to cut only launch-to-first-sync-flop paths.
- Added `mainline_virtual_platform_cdc.xdc` to the main constraint set.

## Not Integrated

- Classmate `LED_WALK_TEST` debug path in `top.sv`.
- Classmate `z_light_decode.sv`, because it lacks local `ENABLE_Z_B_SMALL`
  decode support.
- Classmate whole-file `myCPU.sv`, because it would remove local two-cycle
  Z_B_SMALL implementation.
- xsim/log artifacts in `digital_twin.srcs/new1/new`.

## Checks Run

Vivado RTL elaboration check:

```text
synth_design -rtl -top top
```

Result:

- top: `top`
- Verilog define: empty, so default mainline has `ENABLE_Z_B_SMALL` off
- IPs: `DRAM IROM IROM_BRAM pll`
- Missing instances: none
- Result: 0 errors, 0 critical warnings

Compile order report:

`compile_order_after_300m_integration.rpt`

Confirms synthesis uses:

- `digital_twin.srcs/sources_1/new/myCPU.sv`
- `digital_twin.srcs/sources_1/new/student_top.sv`
- `digital_twin.srcs/sources_1/new/perip_bridge.sv`
- `digital_twin.srcs/sources_1/new/dram_driver.sv`
- synchronous `IROM_BRAM.dcp`

## Next Step

Run a clean 300MHz withMext-v2 implementation using this integrated source
state, then board-test before tagging or committing as a known-good 300MHz
baseline.
