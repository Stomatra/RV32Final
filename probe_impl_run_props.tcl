open_project digital_twin.xpr
set run_obj [get_runs impl_1]
puts "RUN_NAME=[get_property NAME $run_obj]"
puts "RUN_FLOW=[get_property FLOW $run_obj]"
puts "RUN_STRATEGY=[get_property STRATEGY $run_obj]"
set props [report_property -return_string $run_obj]
puts $props
close_project
exit
