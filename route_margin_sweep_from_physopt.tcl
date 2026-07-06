set root_dir [file normalize "."]
set physopt_dcp [file join $root_dir "digital_twin.runs" "impl_1" "top_physopt.dcp"]
set out_dir [file join $root_dir "timing_backups" "route_margin_sweep_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"]
file mkdir $out_dir

set directives {
	Default
	Explore
	AggressiveExplore
	NoTimingRelaxation
	MoreGlobalIterations
	HigherDelayCost
}

set summary_path [file join $out_dir "summary.tsv"]
set summary_chan [open $summary_path w]
puts $summary_chan "route_directive\twns\treport\tdcp"

foreach directive $directives {
	puts "===== ROUTE SWEEP: $directive ====="
	open_checkpoint $physopt_dcp
	if {$directive eq "Default"} {
		route_design -tns_cleanup
	} else {
		route_design -directive $directive -tns_cleanup
	}
	set worst_path [lindex [get_timing_paths -setup -max_paths 1] 0]
	if {$worst_path eq ""} {
		set wns "NA"
	} else {
		set wns [get_property SLACK $worst_path]
	}
	set safe_name [string map {" " "_"} $directive]
	set rpt_path [file join $out_dir "timing_${safe_name}.rpt"]
	set dcp_path [file join $out_dir "top_${safe_name}.dcp"]
	report_timing_summary -max_paths 10 -report_unconstrained -file $rpt_path
	write_checkpoint -force $dcp_path
	puts $summary_chan [format "%s\t%s\t%s\t%s" $directive $wns $rpt_path $dcp_path]
	flush $summary_chan
	close_design
}

close $summary_chan
puts "SUMMARY_FILE=$summary_path"
puts "OUTPUT_DIR=$out_dir"
exit