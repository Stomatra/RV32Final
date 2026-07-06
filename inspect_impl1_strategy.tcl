open_project digital_twin.xpr
set run [get_runs impl_1]
puts "IMPL_STATUS=[get_property STATUS $run]"
puts "IMPL_STRATEGY=[get_property STRATEGY $run]"
puts "IMPL_FLOW=[get_property FLOW $run]"
puts "IMPL_STEPS_PLACE_ARGS=[get_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $run]"
puts "IMPL_STEPS_PHYSOPT_ISENABLED=[get_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED $run]"
puts "IMPL_STEPS_PHYSOPT_ARGS=[get_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE $run]"
puts "IMPL_STEPS_ROUTE_ARGS=[get_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE $run]"
close_project
exit
