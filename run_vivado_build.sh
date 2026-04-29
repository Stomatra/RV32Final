#!/bin/bash
# Vivado re-synthesis and implementation script for mem_load_stall fix

cd /d/digital_twin/digital_twin

# Set Vivado path (adjust for your installation)
export PATH="/c/Xilinx/Vivado/2023.2/bin:$PATH"

# Create TCL script for synthesis and implementation
cat > vivado_build.tcl << 'VIVADO_TCL'
# Open project
open_project digital_twin.xpr

# Reset and run synthesis
reset_runs synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check synthesis results
set synth_status [get_property STATUS [get_runs synth_1]]
if {$synth_status != "synth_design Complete!"} {
    puts "WARNING: Synthesis status: $synth_status"
}
puts "[get_property STATS.SYNTHESIZED [get_runs synth_1]]"

# Reset and run implementation
reset_runs impl_1
launch_runs impl_1 -jobs 8
wait_on_run impl_1

# Generate bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# Report timing
open_run synth_1
report_timing_summary -file /tmp/synth_timing.txt
close_run synth_1

open_run impl_1
report_timing_summary -file /tmp/impl_timing.txt
close_run impl_1

# Close project
close_project
puts "Build complete. Bitfile: digital_twin.runs/impl_1/top.bit"
VIVADO_TCL

# Run Vivado in batch mode
vivado -mode batch -source vivado_build.tcl -log vivado_build.log
echo "Build log saved to vivado_build.log"
