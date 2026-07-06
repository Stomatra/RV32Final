set root_dir [file normalize "."]
set synth_dcp [file join $root_dir "digital_twin.runs" "synth_1" "top.dcp"]
set irom_xci [file join $root_dir "digital_twin.srcs" "sources_1" "ip" "IROM" "IROM.xci"]
set pll_xci [file join $root_dir "digital_twin.srcs" "sources_1" "ip" "pll_1" "pll.xci"]
set xdc_file [file join $root_dir "digital_twin.srcs" "constrs_1" "new" "digital_twin.xdc"]
set out_dir [file join $root_dir "timing_backups" "place_directive_psip_sweep_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"]
file mkdir $out_dir

set configs {
    {place_default {place_design}}
    {place_explore {place_design -directive Explore}}
    {place_aggressive {place_design -directive AggressiveExplore}}
    {place_psip_bram_fanout {place_design -psip_options {bram_register_opt fanout_opt}}}
    {place_explore_psip {place_design -directive Explore -psip_options {bram_register_opt fanout_opt}}}
}

set summary_path [file join $out_dir "summary.tsv"]
set summary_chan [open $summary_path w]
puts $summary_chan "name\twns\treport\tdcp\tstatus"

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

foreach cfg $configs {
    lassign $cfg name place_cmd
    puts "===== PLACE DIRECTIVE SWEEP: $name ====="
    set wns "NA"
    set status "ok"
    set rpt_path [file join $out_dir "timing_${name}.rpt"]
    set dcp_path [file join $out_dir "top_${name}.dcp"]

    if {[catch {
        create_impl_design $name $synth_dcp $irom_xci $pll_xci $xdc_file
        opt_design
        eval $place_cmd
        phys_opt_design
        route_design
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

    puts $summary_chan [format "%s\t%s\t%s\t%s\t%s" $name $wns $rpt_path $dcp_path $status]
    flush $summary_chan
}

close $summary_chan
puts "SUMMARY_FILE=$summary_path"
puts "OUTPUT_DIR=$out_dir"
exit
