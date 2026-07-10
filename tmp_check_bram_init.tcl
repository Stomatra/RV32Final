open_project digital_twin.xpr
open_run synth_1
set brams [get_cells -hier -filter {PRIMITIVE_TYPE =~ BMEM.bram.*}]
puts "BRAM_COUNT=[llength $brams]"
set idx 0
foreach c $brams {
  if {$idx >= 8} {break}
  set n [get_property NAME $c]
  set i00 [get_property INIT_00 $c]
  set i01 [get_property INIT_01 $c]
  puts "CELL=$n"
  puts "  INIT00_LEN=[string length $i00] INIT01_LEN=[string length $i01]"
  incr idx
}
close_project
