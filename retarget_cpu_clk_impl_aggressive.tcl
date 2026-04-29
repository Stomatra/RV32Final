if {[llength $argv] != 1} {
    puts "Usage: vivado -mode batch -source retarget_cpu_clk_impl_aggressive.tcl -tclargs <freq_mhz>"
    exit 1
}

set target_freq [lindex $argv 0]
set freq_tag [regsub -all {\.} $target_freq {p}]

open_project {d:/digital_twin/digital_twin/digital_twin.xpr}

set pll_ip [get_ips pll]
if {[llength $pll_ip] != 1} {
    puts "ERROR: expected exactly one IP named pll"
    close_project
    exit 1
}

set pll_xci [get_files {d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/ip/pll_1/pll.xci}]
if {[llength $pll_xci] != 1} {
    puts "ERROR: expected active pll_1 xci file"
    close_project
    exit 1
}

upgrade_ip $pll_ip
set_property -dict [list CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $target_freq] $pll_ip
reset_target all $pll_xci
generate_target all $pll_xci
export_ip_user_files -of_objects $pll_xci -no_script -sync -force -quiet

if {[llength [get_runs pll_synth_1]] == 0} {
    create_ip_run $pll_xci
}

reset_run pll_synth_1
launch_runs pll_synth_1 -jobs 2
wait_on_run pll_synth_1

update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1

open_run synth_1

# Switch from the default impl_1 run recipe to a more aggressive manual flow.
opt_design -directive Explore
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
phys_opt_design -directive AggressiveExplore

report_clocks -file [format {d:/digital_twin/digital_twin/openrun_impl_clocks_aggr_%sm.rpt} $freq_tag]
report_timing_summary -max_paths 20 -file [format {d:/digital_twin/digital_twin/openrun_top_timing_impl_aggr_%sm.rpt} $freq_tag]
report_utilization -file [format {d:/digital_twin/digital_twin/openrun_top_utilization_impl_aggr_%sm.rpt} $freq_tag]

close_design
close_project
exit