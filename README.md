# RV32Final

This repository tracks the FPGA source for the RV32 project, not local Vivado
project state.

## Recreate the Vivado Project

From the repository root:

```powershell
vivado -mode batch -source scripts/recreate_vivado_project.tcl
```

The script creates a local project at:

```text
build/vivado/digital_twin.xpr
```

Open that generated `.xpr` in Vivado. The `build/` directory is ignored by Git,
so each developer can recreate the project with their own Vivado version.

## What to Commit

Commit source inputs:

- HDL: `.sv`, `.v`, `.svh`, `.vh`
- Constraints: `.xdc`
- Memory init files: `.coe`
- IP configuration: `.xci`
- Build/recreate scripts and documentation

Do not commit generated Vivado state or outputs:

- `.xpr`, `.runs`, `.cache`, `.gen`, `.sim`, `.hw`, `.ip_user_files`
- `.Xil`, `xsim.dir`
- logs, reports, checkpoints, bitstreams, probes, timing backups

If Vivado asks to upgrade IP after opening the project, do it locally only
unless everyone agrees to move the project to that Vivado version.
