open_project digital_twin.xpr
reset_runs synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
reset_runs impl_1
launch_runs impl_1 -jobs 8
wait_on_run impl_1
open_run impl_1
report_timing_summary -max_paths 10 -file timing_summary_after_wb_load_stage.rpt
close_project
exit
