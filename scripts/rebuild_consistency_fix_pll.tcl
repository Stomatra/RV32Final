open_project digital_twin.xpr
set fs [get_filesets sources_1]
set pll_xci_src [file normalize "digital_twin.srcs/sources_1/ip/pll/pll.xci"]
set has_pll_xci [get_files -quiet -of_objects $fs *sources_1/ip/pll/pll.xci]
if {[llength $has_pll_xci] == 0 && [file exists $pll_xci_src]} {
  puts "CONSISTENCY3 add pll.xci to sources_1: $pll_xci_src"
  add_files -norecurse -fileset $fs $pll_xci_src
}
set pll_v_src [file normalize "digital_twin.gen/sources_1/ip/pll/pll.v"]
if {[file exists $pll_v_src]} {
  set has_pll_v [get_files -quiet -of_objects $fs $pll_v_src]
  if {[llength $has_pll_v] == 0} {
    puts "CONSISTENCY3 add pll.v to sources_1: $pll_v_src"
    add_files -norecurse -fileset $fs $pll_v_src
  }
}
set pll_clk_wiz_src [file normalize "digital_twin.gen/sources_1/ip/pll/pll_clk_wiz.v"]
if {[file exists $pll_clk_wiz_src]} {
  set has_pll_clk_wiz [get_files -quiet -of_objects $fs $pll_clk_wiz_src]
  if {[llength $has_pll_clk_wiz] == 0} {
    puts "CONSISTENCY3 add pll_clk_wiz.v to sources_1: $pll_clk_wiz_src"
    add_files -norecurse -fileset $fs $pll_clk_wiz_src
  }
}
update_compile_order -fileset sources_1
puts "CONSISTENCY3 FS_PLL_XCI=[get_files -quiet -of_objects $fs *sources_1/ip/pll/pll.xci]"
puts "CONSISTENCY3 launch synth/impl"
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
puts "CONSISTENCY3 synth_1 STATUS=[get_property STATUS [get_runs synth_1]]"
puts "CONSISTENCY3 synth_1 PROGRESS=[get_property PROGRESS [get_runs synth_1]]"
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "CONSISTENCY3 impl_1 STATUS=[get_property STATUS [get_runs impl_1]]"
puts "CONSISTENCY3 impl_1 PROGRESS=[get_property PROGRESS [get_runs impl_1]]"
puts "CONSISTENCY3 impl_1 DIR=[get_property DIRECTORY [get_runs impl_1]]"
close_project
