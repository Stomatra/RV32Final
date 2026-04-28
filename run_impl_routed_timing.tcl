open_project {d:/digital_twin/digital_twin/digital_twin.xpr}
reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1
open_run impl_1
report_clocks -file {d:/digital_twin/digital_twin/openrun_impl_clocks.rpt}
report_timing_summary -max_paths 10 -file {d:/digital_twin/digital_twin/openrun_top_timing_impl.rpt}
report_utilization -file {d:/digital_twin/digital_twin/openrun_top_utilization_impl.rpt}
close_project
exit
