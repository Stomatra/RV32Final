open_project digital_twin.xpr
set run [get_runs impl_1]
set_property STRATEGY {Vivado Implementation Defaults} $run
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE {Explore} $run
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $run
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE {Default} $run
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE {Default} $run
puts "UPDATED_IMPL_STATUS=[get_property STATUS $run]"
puts "UPDATED_IMPL_STRATEGY=[get_property STRATEGY $run]"
puts "UPDATED_IMPL_FLOW=[get_property FLOW $run]"
puts "UPDATED_IMPL_PLACE_ARGS=[get_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $run]"
puts "UPDATED_IMPL_PHYSOPT_ENABLED=[get_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED $run]"
puts "UPDATED_IMPL_PHYSOPT_ARGS=[get_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE $run]"
puts "UPDATED_IMPL_ROUTE_ARGS=[get_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE $run]"
save_project_as digital_twin.xpr
close_project
exit
