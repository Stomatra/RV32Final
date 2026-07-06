set root_dir [file normalize "."]
set baseline_dcp [file join $root_dir "timing_backups" "baseline_200mhz_explore" "top_200mhz_baseline.dcp"]
set out_dir [file join $root_dir "timing_backups" "incremental_from_baseline_202p25_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"]
file mkdir $out_dir
set report_path [file join $out_dir "timing_202p25_incremental.rpt"]
set dcp_path [file join $out_dir "top_202p25_incremental.dcp"]
set summary_path [file join $out_dir "summary.txt"]

proc cleanup_run_markers {run_dir} {
    foreach pattern {.stop.rst .vivado.begin.rst .vivado.end.rst .vivado.error.rst __synthesis_is_running__ __implementation_is_running__} {
        foreach stale_file [glob -nocomplain -directory $run_dir $pattern] {
            catch {file delete -force $stale_file}
        }
    }
}

# First regenerate pll at 202.25 MHz and rebuild synth_1.
open_project [file join $root_dir "digital_twin.xpr"]
set srcset [get_filesets sources_1]
catch {
    set old_import_mycpu [get_files -of_objects $srcset [file join $root_dir "digital_twin.srcs" "sources_1" "imports" "new" "myCPU.sv"]]
    if {[llength $old_import_mycpu] > 0} {
        remove_files $old_import_mycpu
    }
}
set mycpu_file_new [get_files -of_objects $srcset [file join $root_dir "digital_twin.srcs" "sources_1" "new" "myCPU.sv"]]
if {[llength $mycpu_file_new] == 0} {
    add_files -fileset $srcset -norecurse [file join $root_dir "digital_twin.srcs" "sources_1" "new" "myCPU.sv"]
}
update_compile_order -fileset sources_1
set pll_ip [get_ips pll]
set pll_xci_path [file join $root_dir "digital_twin.srcs" "sources_1" "ip" "pll_1" "pll.xci"]
set pll_xci [get_files $pll_xci_path]
if {[llength $pll_ip] != 1 || [llength $pll_xci] != 1} { error "Could not resolve pll IP" }
upgrade_ip $pll_ip
set_property -dict [list CONFIG.PRIMITIVE {PLL} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 50.0 CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 202.25] $pll_ip
reset_target all $pll_xci
generate_target all $pll_xci
export_ip_user_files -of_objects $pll_xci -no_script -sync -force -quiet
if {[llength [get_runs pll_synth_1]] == 0} { create_ip_run $pll_xci }
cleanup_run_markers [file normalize [file join $root_dir "digital_twin.runs" "pll_synth_1"]]
reset_run pll_synth_1
launch_runs pll_synth_1 -jobs 2
wait_on_run pll_synth_1
cleanup_run_markers [file normalize [file join $root_dir "digital_twin.runs" "synth_1"]]
reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
close_project

# Then run non-project incremental implementation from the best 200 MHz routed DCP.
set synth_dcp [file join $root_dir "digital_twin.runs" "synth_1" "top.dcp"]
set irom_xci_path [file join $root_dir "digital_twin.srcs" "sources_1" "ip" "IROM" "IROM.xci"]
set xdc_file [file join $root_dir "digital_twin.srcs" "constrs_1" "new" "digital_twin.xdc"]
create_project -in_memory incremental_202p25 -part xc7k325tffg900-2
set_property design_mode GateLvl [current_fileset]
set_property parent.project_path [file normalize "./digital_twin.xpr"] [current_project]
set_property ip_output_repo [file normalize "./digital_twin.cache/ip"] [current_project]
set_property ip_cache_permissions {read write} [current_project]
add_files -quiet $synth_dcp
read_ip -quiet $irom_xci_path
read_ip -quiet $pll_xci_path
read_xdc $xdc_file
link_design -top top -part xc7k325tffg900-2
read_checkpoint -incremental $baseline_dcp
report_incremental_reuse -file [file join $out_dir "incremental_reuse.rpt"]
opt_design
place_design -directive Explore
phys_opt_design
route_design -timing_summary
set worst_path [lindex [get_timing_paths -setup -max_paths 1] 0]
if {$worst_path ne ""} {
    set final_wns [get_property SLACK $worst_path]
} else {
    set final_wns "NA"
}
report_timing_summary -max_paths 10 -report_unconstrained -file $report_path
write_checkpoint -force $dcp_path
set summary_chan [open $summary_path w]
puts $summary_chan "FINAL_WNS=$final_wns"
puts $summary_chan "REPORT_PATH=$report_path"
puts $summary_chan "DCP_PATH=$dcp_path"
close $summary_chan
close_project

# Restore baseline project PLL back to 200 MHz.
catch {
    open_project [file join $root_dir "digital_twin.xpr"]
    set pll_ip [get_ips pll]
    set pll_xci [get_files $pll_xci_path]
    upgrade_ip $pll_ip
    set_property -dict [list CONFIG.PRIMITIVE {PLL} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 50.0 CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 200.0] $pll_ip
    reset_target all $pll_xci
    generate_target all $pll_xci
    export_ip_user_files -of_objects $pll_xci -no_script -sync -force -quiet
    close_project
}
puts "SUMMARY_FILE=$summary_path"
puts "REPORT_PATH=$report_path"
puts "DCP_PATH=$dcp_path"
exit
