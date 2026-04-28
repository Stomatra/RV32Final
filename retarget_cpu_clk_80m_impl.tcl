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

set_property -dict [list CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {80.000}] $pll_ip
generate_target all $pll_xci

reset_run synth_1
reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1

open_run impl_1
report_clocks -file {d:/digital_twin/digital_twin/openrun_impl_clocks_80m.rpt}
report_timing_summary -max_paths 10 -file {d:/digital_twin/digital_twin/openrun_top_timing_impl_80m.rpt}
report_utilization -file {d:/digital_twin/digital_twin/openrun_top_utilization_impl_80m.rpt}
close_project
exit