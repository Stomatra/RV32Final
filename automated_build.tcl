
set repo_dir [file normalize [file dirname [info script]]]
set build_dir [file join $repo_dir build]
file mkdir $build_dir
set project_file [file join $repo_dir build vivado digital_twin.xpr]
if {![file exists $project_file]} {
    source [file join $repo_dir scripts recreate_vivado_project.tcl]
}
open_project $project_file

# Synthesis
puts "\n===== SYNTHESIS ====="
reset_runs synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check synthesis
open_run synth_1
puts [get_property STATS.SYNTHESIZED [get_runs synth_1]]
report_timing_summary -file [file join $build_dir synth_timing_summary.txt]
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
report_timing_summary -file [file join $build_dir impl_timing_summary.txt]
puts "\nTiming Report:"
catch {exec grep -i "slack" [file join $build_dir impl_timing_summary.txt]}
close_run impl_1

puts "\n===== BUILD COMPLETE ====="
set bitfile [file join [get_property DIRECTORY [current_project]] digital_twin.runs impl_1 top.bit]
puts "Bitfile: $bitfile"
close_project
