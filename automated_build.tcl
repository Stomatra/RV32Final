
open_project digital_twin.xpr

# Synthesis
puts "\n===== SYNTHESIS ====="
reset_runs synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check synthesis
open_run synth_1
puts [get_property STATS.SYNTHESIZED [get_runs synth_1]]
report_timing_summary -file synth_timing_summary.txt
close_run synth_1

# Implementation
puts "\n===== IMPLEMENTATION ====="
reset_runs impl_1
launch_runs impl_1 -jobs 8
wait_on_run impl_1

# Generate bitstream
puts "\n===== BITSTREAM GENERATION ====="
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# Report timing
open_run impl_1
report_timing_summary -file impl_timing_summary.txt
puts "\nTiming Report:"
catch {exec grep -i "slack" impl_timing_summary.txt}
close_run impl_1

puts "\n===== BUILD COMPLETE ====="
puts "Bitfile: digital_twin.runs/impl_1/top.bit"
close_project
