open_project digital_twin.xpr
reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
puts "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
puts "SYNTH_DCP=[file normalize ./digital_twin.runs/synth_1/top.dcp]"
close_project
exit
