open_project {e:/Projects/1Aprojects/RV32Final/digital_twin.xpr}

set srcset [get_filesets sources_1]
catch {
    set old_import_mycpu [get_files -of_objects $srcset {e:/Projects/1Aprojects/RV32Final/digital_twin.srcs/sources_1/imports/new/myCPU.sv}]
    if {[llength $old_import_mycpu] > 0} {
        remove_files $old_import_mycpu
    }
}
set mycpu_file_new [get_files -of_objects $srcset {e:/Projects/1Aprojects/RV32Final/digital_twin.srcs/sources_1/new/myCPU.sv}]
if {[llength $mycpu_file_new] == 0} {
    add_files -fileset $srcset -norecurse {e:/Projects/1Aprojects/RV32Final/digital_twin.srcs/sources_1/new/myCPU.sv}
}
update_compile_order -fileset sources_1

set pll_ip [get_ips pll]
set pll_xci [get_files {e:/Projects/1Aprojects/RV32Final/digital_twin.srcs/sources_1/ip/pll_1/pll.xci}]
if {[llength $pll_ip] != 1 || [llength $pll_xci] != 1} {
    puts "ERROR: Could not resolve pll IP or pll_1 xci"
    close_project
    exit 1
}

upgrade_ip $pll_ip
set_property -dict [list CONFIG.PRIMITIVE {PLL} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 50.0 CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 202.25] $pll_ip
reset_target all $pll_xci
generate_target all $pll_xci
export_ip_user_files -of_objects $pll_xci -no_script -sync -force -quiet

if {[llength [get_runs pll_synth_1]] == 0} {
    create_ip_run $pll_xci
}
reset_run pll_synth_1
launch_runs pll_synth_1 -jobs 2
wait_on_run pll_synth_1

if {[llength [get_runs synth_1]] == 0} {
    puts "ERROR: synth_1 run not found"
    close_project
    exit 1
}
reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1

set run_name impl_202p25_explore
if {[llength [get_runs $run_name]] == 0} {
    create_run -name $run_name -parent_run synth_1 -part xc7k325tffg900-2 -flow {Vivado Implementation 2023} -strategy {Vivado Implementation Defaults} -constrset constrs_1
}
set run_obj [get_runs $run_name]
set_property strategy {Vivado Implementation Defaults} $run_obj
set_property INCREMENTAL_CHECKPOINT {e:/Projects/1Aprojects/RV32Final/timing_backups/baseline_200mhz_explore/top_200mhz_baseline.dcp} $run_obj
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE {Explore} $run_obj
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $run_obj
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE {Default} $run_obj
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $run_obj
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE {Default} $run_obj
reset_run $run_name
launch_runs $run_name -to_step route_design -jobs 2
wait_on_run $run_name
open_run $run_name
report_timing_summary -max_paths 20 -file {e:/Projects/1Aprojects/RV32Final/timing_backups/impl_202p25_explore_timing.rpt}
report_utilization -file {e:/Projects/1Aprojects/RV32Final/timing_backups/impl_202p25_explore_util.rpt}
puts "RUN_STATUS=[get_property STATUS $run_obj]"
set worst_path [lindex [get_timing_paths -setup -max_paths 1] 0]
if {$worst_path ne ""} {
    puts "FINAL_WNS=[get_property SLACK $worst_path]"
}
close_project
exit
