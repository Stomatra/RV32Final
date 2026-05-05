open_project D:/digital_twin/digital_twin/digital_twin.xpr
open_run impl_1
set lanes [get_cells -hier -filter {NAME =~ *dram_lane* && PRIMITIVE_TYPE =~ BMEM.bram.RAMB36E1}]
puts "LANE_CELL_COUNT=[llength $lanes]"
set idx 0
foreach c $lanes {
  if {$idx >= 4} {break}
  puts "CELL=[get_property NAME $c]"
  puts "INIT_00=[get_property INIT_00 $c]"
  puts "INIT_01=[get_property INIT_01 $c]"
  incr idx
}
close_project
