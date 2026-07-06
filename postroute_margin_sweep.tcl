set origin_dir [pwd]
set checkpoint_file [file normalize "./digital_twin.runs/impl_1/top_routed.dcp"]
set report_dir [file normalize "./timing_backups/postroute_sweep_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"]
file mkdir $report_dir

set directives {
	Explore
	AggressiveExplore
	AggressiveFanoutOpt
	AlternateReplication
}

set summary_file [file join $report_dir "summary.txt"]
set summary_chan [open $summary_file w]
puts $summary_chan "Checkpoint: $checkpoint_file"
puts $summary_chan "ReportDir: $report_dir"

proc record_result {chan directive slack report_path dcp_path} {
	puts $chan [format "%s\t%s\t%s\t%s" $directive $slack $report_path $dcp_path]
	flush $chan
}

set baseline_design [file normalize "./digital_twin.runs/impl_1/top_routed.dcp"]

foreach directive $directives {
	puts "===== POSTROUTE SWEEP: $directive ====="
	open_checkpoint $baseline_design
	phys_opt_design -directive $directive
	route_design -preserve -tns_cleanup -directive Explore
	set worst_path [lindex [get_timing_paths -setup -max_paths 1] 0]
	if {$worst_path eq ""} {
		set slack "NA"
	} else {
		set slack [get_property SLACK $worst_path]
	}
	set rpt_path [file join $report_dir "timing_${directive}.rpt"]
	set dcp_path [file join $report_dir "top_${directive}.dcp"]
	report_timing_summary -max_paths 10 -report_unconstrained -file $rpt_path
	write_checkpoint -force $dcp_path
	record_result $summary_chan $directive $slack $rpt_path $dcp_path
	close_design
}

close $summary_chan
puts "SUMMARY_FILE=$summary_file"
puts "REPORT_DIR=$report_dir"
exit