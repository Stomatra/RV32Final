set root_dir [file normalize "."]
set synth_dcp [file join $root_dir "digital_twin.runs" "synth_1" "top.dcp"]
set irom_xci [file join $root_dir "digital_twin.srcs" "sources_1" "ip" "IROM" "IROM.xci"]
set pll_xci [file join $root_dir "digital_twin.srcs" "sources_1" "ip" "pll_1" "pll.xci"]
set xdc_file [file join $root_dir "digital_twin.srcs" "constrs_1" "new" "digital_twin.xdc"]
set out_dir [file join $root_dir "timing_backups" "single_explore_uncertainty_202p25_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"]
file mkdir $out_dir

proc create_impl_design {name synth_dcp irom_xci pll_xci xdc_file} {
    create_project -in_memory $name -part xc7k325tffg900-2
    set_property design_mode GateLvl [current_fileset]
    set_property parent.project_path [file normalize "./digital_twin.xpr"] [current_project]
    set_property ip_output_repo [file normalize "./digital_twin.cache/ip"] [current_project]
    set_property ip_cache_permissions {read write} [current_project]
    add_files -quiet $synth_dcp
    read_ip -quiet $irom_xci
    read_ip -quiet $pll_xci
    read_xdc $xdc_file
    link_design -top top -part xc7k325tffg900-2
}

set name "Explore202p25"
set wns "NA"
set status "ok"
set rpt_path [file join $out_dir "timing_${name}.rpt"]
set dcp_path [file join $out_dir "top_${name}.dcp"]
set summary_path [file join $out_dir "summary.tsv"]
set delta [expr {5.000 - (1000.0 / 202.25)}]

if {[catch {
    create_impl_design $name $synth_dcp $irom_xci $pll_xci $xdc_file
    set_clock_uncertainty $delta [get_clocks clk_out2_pll]
    opt_design
    place_design -directive Explore
    phys_opt_design
    route_design -timing_summary
    set worst_path [lindex [get_timing_paths -setup -max_paths 1] 0]
    if {$worst_path ne ""} {
        set wns [get_property SLACK $worst_path]
    }
    report_timing_summary -max_paths 10 -report_unconstrained -file $rpt_path
    write_checkpoint -force $dcp_path
    close_project
} err]} {
    set status $err
    catch {close_project}
}

set summary_chan [open $summary_path w]
puts $summary_chan "directive\twns\treport\tdcp\tstatus"
puts $summary_chan [format "%s\t%s\t%s\t%s\t%s" $name $wns $rpt_path $dcp_path $status]
close $summary_chan

puts "PERIOD_DELTA=$delta"
puts "SUMMARY_FILE=$summary_path"
puts "OUTPUT_DIR=$out_dir"
exit
