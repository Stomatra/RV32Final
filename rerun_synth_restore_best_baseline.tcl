open_project digital_twin.xpr
reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
puts "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
close_project
exit
