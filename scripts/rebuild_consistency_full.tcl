set proj_path [file normalize "digital_twin.xpr"]
puts "CONSISTENCY2 opening project: $proj_path"
open_project $proj_path

set src_fs [get_filesets sources_1]

puts "CONSISTENCY2 reset_target all [get_ips]"
reset_target all [get_ips]
puts "CONSISTENCY2 generate_target all [get_ips]"
generate_target all [get_ips]

# Defensive: ensure PLL wrapper and helper module are visible to top-level synthesis.
set pll_wrapper_file [file normalize "digital_twin.gen/sources_1/ip/pll/pll.v"]
if {[file exists $pll_wrapper_file]} {
  set in_fs [get_files -quiet -of_objects $src_fs $pll_wrapper_file]
  if {[llength $in_fs] == 0} {
    puts "CONSISTENCY2 add_files sources_1 $pll_wrapper_file"
    add_files -norecurse -fileset $src_fs $pll_wrapper_file
  }
} else {
  puts "CONSISTENCY2 WARN pll.v not found at $pll_wrapper_file"
}

set pll_clk_wiz_file [file normalize "digital_twin.gen/sources_1/ip/pll/pll_clk_wiz.v"]
if {[file exists $pll_clk_wiz_file]} {
  set in_fs [get_files -quiet -of_objects $src_fs $pll_clk_wiz_file]
  if {[llength $in_fs] == 0} {
    puts "CONSISTENCY2 add_files sources_1 $pll_clk_wiz_file"
    add_files -norecurse -fileset $src_fs $pll_clk_wiz_file
  }
} else {
  puts "CONSISTENCY2 WARN pll_clk_wiz.v not found at $pll_clk_wiz_file"
}
update_compile_order -fileset sources_1

puts "CONSISTENCY2 reset_run synth_1"
reset_run synth_1
puts "CONSISTENCY2 launch_runs synth_1"
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set synth_run [get_runs synth_1]
puts "CONSISTENCY2 synth_1 STATUS=[get_property STATUS $synth_run]"
puts "CONSISTENCY2 synth_1 PROGRESS=[get_property PROGRESS $synth_run]"

puts "CONSISTENCY2 reset_run impl_1"
reset_run impl_1
puts "CONSISTENCY2 launch_runs impl_1 -to_step write_bitstream"
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set impl_run [get_runs impl_1]
puts "CONSISTENCY2 impl_1 STATUS=[get_property STATUS $impl_run]"
puts "CONSISTENCY2 impl_1 PROGRESS=[get_property PROGRESS $impl_run]"
puts "CONSISTENCY2 impl_1 DIRECTORY=[get_property DIRECTORY $impl_run]"

set irom_ip [get_ips IROM]
set dram_ip [get_ips DRAM]
if {[llength $irom_ip] > 0} {
  puts "CONSISTENCY2 IROM CONFIG.Coe_File=[get_property CONFIG.Coe_File $irom_ip]"
}
if {[llength $dram_ip] > 0} {
  puts "CONSISTENCY2 DRAM CONFIG.Coe_File=[get_property CONFIG.Coe_File $dram_ip]"
}

close_project
puts "CONSISTENCY2 done"
