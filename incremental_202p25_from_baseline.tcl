set root_dir [file normalize "."]
set baseline_dcp [file join $root_dir "timing_backups" "baseline_200mhz_explore" "top_200mhz_baseline.dcp"]
set out_dir [file join $root_dir "timing_backups" "incremental_202p25_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"]
file mkdir $out_dir
set report_path [file join $out_dir "timing_202p25_incremental.rpt"]
set dcp_path [file join $out_dir "top_202p25_incremental.dcp"]
set target_period [expr {1000.0 / 202.25}]

create_project -in_memory incremental_202p25 -part xc7k325tffg900-2
set_property design_mode GateLvl [current_fileset]
set_property parent.project_path [file normalize "./digital_twin.xpr"] [current_project]
set_property ip_output_repo [file normalize "./digital_twin.cache/ip"] [current_project]
set_property ip_cache_permissions {read write} [current_project]
add_files -quiet $baseline_dcp
read_xdc [file join $root_dir "digital_twin.srcs" "constrs_1" "new" "digital_twin.xdc"]
link_design -reconfig_partitions {} -mode default -part xc7k325tffg900-2 -top top

# Tighten the cpu clock requirement in-place for a what-if incremental run.
set clk [get_clocks clk_out2_pll]
set src_pin [get_property SOURCE_PINS $clk]
if {[llength $src_pin] == 0} {
    error "Could not resolve source pin for clk_out2_pll"
}
create_generated_clock -name clk_out2_pll_202p25 -source [get_ports i_sys_clk_p] -master_clock i_sys_clk_p -divide_by 1 $src_pin
set old_clk [get_clocks clk_out2_pll]
if {[llength $old_clk] > 0} { catch {delete_clocks $old_clk} }
create_clock -name clk_out2_pll -period $target_period [get_pins [lindex $src_pin 0]]

phys_opt_design -directive Explore
route_design -directive Explore -timing_summary
set worst_path [lindex [get_timing_paths -setup -max_paths 1] 0]
if {$worst_path ne ""} {
    set final_wns [get_property SLACK $worst_path]
} else {
    set final_wns NA
}
report_timing_summary -max_paths 10 -report_unconstrained -file $report_path
write_checkpoint -force $dcp_path
puts "FINAL_WNS=$final_wns"
puts "REPORT_PATH=$report_path"
puts "DCP_PATH=$dcp_path"
close_project
exit
