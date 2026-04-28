open_project {d:/digital_twin/digital_twin/digital_twin.xpr}
reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
open_run synth_1
report_utilization -file {d:/digital_twin/digital_twin/current_top_utilization_synth.rpt}
report_timing_summary -max_paths 10 -file {d:/digital_twin/digital_twin/current_top_timing_synth.rpt}
close_project
exit
