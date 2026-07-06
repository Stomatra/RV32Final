open_project digital_twin.xpr
set run_obj [get_runs impl_202p25_explore]
puts "RUN_EXISTS=[llength $run_obj]"
if {[llength $run_obj] > 0} {
  puts "STATUS=[get_property STATUS $run_obj]"
  puts "PROGRESS=[get_property PROGRESS $run_obj]"
  puts "CURRENT_STEP=[get_property CURRENT_STEP $run_obj]"
  puts "WNS=[get_property STATS.WNS $run_obj]"
  puts "TNS=[get_property STATS.TNS $run_obj]"
  puts "DIRECTORY=[get_property DIRECTORY $run_obj]"
}
close_project
exit
