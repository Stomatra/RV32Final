create_project query_sites build_outputs/query_sites_proj -part xc7k325tffg900-2 -force
link_design -part xc7k325tffg900-2
puts "MMCM sites:"
foreach s [lsort [get_sites -filter {SITE_TYPE =~ MMCME2_ADV}]] {
  puts "$s CLOCK_REGION=[get_property CLOCK_REGION $s]"
}
puts "BUFIO sites X0:"
foreach s [lsort [get_sites BUFIO_X0Y*]] {
  puts "$s CLOCK_REGION=[get_property CLOCK_REGION $s]"
}
puts "HDMI package pin sites:"
foreach p {D27 C27 B30 A30 G29 F30 H30 G30 AD12 AD11 D17 D29} {
  set site [get_sites -of_objects [get_package_pins $p]]
  puts "$p site=$site site_type=[get_property SITE_TYPE $site] clock_region=[get_property CLOCK_REGION $site]"
}
exit
