set root_dir [file normalize "."]
set routed_dcp [file join $root_dir "digital_twin.runs" "impl_1" "top_routed.dcp"]
set out_dir [file join $root_dir "timing_backups" "postroute_forced_physopt_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"]
file mkdir $out_dir

set configs {
    {cpin_place_route {-critical_pin_opt -placement_opt -routing_opt -critical_cell_opt}}
    {fanout_cpin_route {-fanout_opt -critical_pin_opt -placement_opt -routing_opt -critical_cell_opt}}
    {lut_cpin_route {-lut_opt -critical_pin_opt -placement_opt -routing_opt -critical_cell_opt}}
}

set summary_path [file join $out_dir "summary.tsv"]
set summary_chan [open $summary_path w]
puts $summary_chan "name\twns\treport\tdcp\tstatus"

foreach cfg $configs {
    lassign $cfg name args
    puts "===== FORCED POSTROUTE PHYSOPT: $name ====="
    set wns "NA"
    set status "ok"
    set rpt_path [file join $out_dir "timing_${name}.rpt"]
    set dcp_path [file join $out_dir "top_${name}.dcp"]

    if {[catch {
        open_checkpoint $routed_dcp
        set cmd [concat phys_opt_design $args]
        eval $cmd
        route_design -preserve -tns_cleanup -timing_summary
        set worst_path [lindex [get_timing_paths -setup -max_paths 1] 0]
        if {$worst_path ne ""} {
            set wns [get_property SLACK $worst_path]
        }
        report_timing_summary -max_paths 10 -report_unconstrained -file $rpt_path
        write_checkpoint -force $dcp_path
        close_design
    } err]} {
        set status $err
        catch {close_design}
    }

    puts $summary_chan [format "%s\t%s\t%s\t%s\t%s" $name $wns $rpt_path $dcp_path $status]
    flush $summary_chan
}

close $summary_chan
puts "SUMMARY_FILE=$summary_path"
puts "OUTPUT_DIR=$out_dir"
exit
