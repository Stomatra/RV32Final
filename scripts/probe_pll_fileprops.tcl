open_project digital_twin.xpr
set fs [get_filesets sources_1]
puts "CONSISTENCY4 files in sources_1 matching pll*:"
foreach f [get_files -quiet -of_objects $fs *pll*] {
  puts "F=$f FILE_TYPE=[get_property FILE_TYPE $f] USED_IN_SYNTH=[get_property USED_IN_SYNTHESIS $f]"
}
puts "CONSISTENCY4 ip pll files:"
foreach f [get_files -quiet -of_objects [get_ips pll]] {
  puts "IPF=$f FILE_TYPE=[get_property FILE_TYPE $f] USED_IN_SYNTH=[get_property USED_IN_SYNTHESIS $f]"
}
close_project
