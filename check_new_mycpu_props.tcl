open_project d:/digital_twin/digital_twin/digital_twin.xpr
set f [get_files d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/new/myCPU.sv]
puts "COUNT=[llength $f]"
if {[llength $f] > 0} {
  puts "IS_ENABLED=[get_property IS_ENABLED $f]"
  puts "USED_IN_SYNTHESIS=[get_property USED_IN_SYNTHESIS $f]"
  puts "USED_IN=[get_property USED_IN $f]"
  puts "FILE_TYPE=[get_property FILE_TYPE $f]"
  puts "AUTO_DISABLED_PROP=[catch {get_property AUTO_DISABLED $f} v];VAL=$v"
}
close_project
exit
