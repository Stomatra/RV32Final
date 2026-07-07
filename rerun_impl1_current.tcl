open_project digital_twin.xpr
reset_run impl_1
launch_runs impl_1 -jobs 2
wait_on_run impl_1
puts "IMPL_STATUS=[get_property STATUS [get_runs impl_1]]"
puts "TIMING_RPT=[file normalize ./digital_twin.runs/impl_1/top_timing_summary_routed.rpt]"
puts "TIMING_RPT_EXISTS=[file exists ./digital_twin.runs/impl_1/top_timing_summary_routed.rpt]"
close_project
exit
