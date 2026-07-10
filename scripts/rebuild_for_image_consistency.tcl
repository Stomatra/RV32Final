set proj_path [file normalize "digital_twin.xpr"]
puts "CONSISTENCY opening project: $proj_path"
open_project $proj_path

puts "CONSISTENCY reset_target all [get_ips]"
reset_target all [get_ips]
puts "CONSISTENCY generate_target all [get_ips]"
generate_target all [get_ips]

puts "CONSISTENCY reset_run synth_1"
reset_run synth_1
puts "CONSISTENCY reset_run impl_1"
reset_run impl_1

puts "CONSISTENCY launch_runs impl_1 -to_step write_bitstream"
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set irom_ip [get_ips IROM]
set dram_ip [get_ips DRAM]
if {[llength $irom_ip] > 0} {
  puts "CONSISTENCY IROM CONFIG.Coe_File=[get_property CONFIG.Coe_File $irom_ip]"
}
if {[llength $dram_ip] > 0} {
  puts "CONSISTENCY DRAM CONFIG.Coe_File=[get_property CONFIG.Coe_File $dram_ip]"
}

set impl_run [get_runs impl_1]
puts "CONSISTENCY impl_1 STATUS=[get_property STATUS $impl_run]"
puts "CONSISTENCY impl_1 PROGRESS=[get_property PROGRESS $impl_run]"
puts "CONSISTENCY impl_1 DIRECTORY=[get_property DIRECTORY $impl_run]"

close_project
puts "CONSISTENCY done"
