set project_root [file normalize [pwd]]
set xpr [file join $project_root "digital_twin.xpr"]
set out_dir [file join $project_root "build_outputs"]
set final_dir [file join $project_root "final_bits"]
set build_bit [file join $out_dir "WITHMEXT_irom_v2_200m_NORMAL_BUILDID_2A00200A.build.bit"]
set final_bit [file join $final_dir "WITHMEXT_irom_v2_200m_NORMAL_BUILDID_2A00200A.bit"]
set timing_rpt [file join $out_dir "timing_WITHMEXT_irom_v2_200m_NORMAL_BUILDID_2A00200A.rpt"]
set paths_rpt [file join $out_dir "timing_paths_WITHMEXT_irom_v2_200m_NORMAL_BUILDID_2A00200A.rpt"]
set clocks_rpt [file join $out_dir "clocks_WITHMEXT_irom_v2_200m_NORMAL_BUILDID_2A00200A.rpt"]
set summary_txt [file join $out_dir "summary_WITHMEXT_irom_v2_200m_NORMAL_BUILDID_2A00200A.txt"]
set jobs 8
set build_id "32'h2A00200A"

file mkdir $out_dir
file mkdir $final_dir

proc path_pin_name {path prop fallback_prop} {
    if {[catch {set pin [get_property $prop $path]}] || $pin eq ""} {
        if {[catch {set pin [get_property $fallback_prop $path]}] || $pin eq ""} {
            return ""
        }
    }
    return [get_property NAME $pin]
}

proc run_is_ok {run_name} {
    set status [get_property STATUS [get_runs $run_name]]
    if {[string first "ERROR" $status] >= 0 || [string first "Failed" $status] >= 0} {
        error "$run_name failed: $status"
    }
}

puts "OPEN_PROJECT=$xpr"
open_project $xpr

set fs [get_filesets sources_1]
set_property verilog_define {} $fs
puts "VERILOG_DEFINE=[get_property verilog_define $fs]"
if {[string first "DEBUG" [get_property verilog_define $fs]] >= 0} {
    error "DEBUG macro remains in sources_1 verilog_define"
}
if {[string first "LED_WALK_TEST" [get_property verilog_define $fs]] >= 0} {
    error "LED_WALK_TEST remains in sources_1 verilog_define"
}

set_property top top $fs
update_compile_order -fileset sources_1

set pll_ips [get_ips -quiet pll]
if {[llength $pll_ips] == 0} {
    set pll_ips [get_ips -quiet *pll*]
}
if {[llength $pll_ips] == 0} {
    error "Cannot find PLL IP"
}
foreach pll_ip $pll_ips {
    puts "CONFIGURE_PLL=$pll_ip CLKOUT2=200.0"
    set_property -dict [list CONFIG.PRIMITIVE {PLL} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 50.0 CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 200.0] $pll_ip
}

puts "REGENERATE_IP_OUTPUT_PRODUCTS=[get_ips]"
generate_target all [get_ips] -force

set ip_runs [get_runs -quiet *_synth_1]
if {[llength $ip_runs] > 0} {
    foreach r $ip_runs {
        catch {reset_run $r}
    }
    launch_runs $ip_runs -jobs $jobs
    foreach r $ip_runs {
        wait_on_run $r
        run_is_ok $r
    }
}

puts "RESET_SYNTH_1"
catch {reset_run synth_1}
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
run_is_ok synth_1

set impl_run [get_runs impl_1]
set_property strategy Performance_Explore $impl_run
catch {
    set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $impl_run
    set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore $impl_run
}

puts "RESET_IMPL_1"
catch {reset_run impl_1}
launch_runs impl_1 -to_step route_design -jobs $jobs
wait_on_run impl_1
run_is_ok impl_1

open_run impl_1

puts "BUILD_ID=$build_id"
set_property BITSTREAM.CONFIG.USERID $build_id [current_design]
puts "BITSTREAM_CONFIG_USERID=[get_property BITSTREAM.CONFIG.USERID [current_design]]"

report_clocks -file $clocks_rpt
report_timing_summary -file $timing_rpt -delay_type max -report_unconstrained -check_timing_verbose
report_timing -delay_type max -max_paths 10 -sort_by group -file $paths_rpt

write_bitstream -force $build_bit
file copy -force $build_bit $final_bit

set worst_paths [get_timing_paths -setup -max_paths 1 -nworst 1]
set worst_slack ""
set worst_source ""
set worst_dest ""
if {[llength $worst_paths] > 0} {
    set worst_path [lindex $worst_paths 0]
    set worst_slack [get_property SLACK $worst_path]
    set worst_source [path_pin_name $worst_path STARTPOINT_PIN STARTPOINT]
    set worst_dest [path_pin_name $worst_path ENDPOINT_PIN ENDPOINT]
}

set clk_period ""
set clk_freq ""
set cpu_clks [get_clocks -quiet clk_out2_pll]
if {[llength $cpu_clks] > 0} {
    set clk_period [get_property PERIOD [lindex $cpu_clks 0]]
    if {$clk_period ne "" && $clk_period != 0} {
        set clk_freq [expr {1000.0 / $clk_period}]
    }
}

set fp [open $summary_txt w]
puts $fp "BUILD_ID=$build_id"
puts $fp "BITSTREAM_CONFIG_USERID=[get_property BITSTREAM.CONFIG.USERID [current_design]]"
puts $fp "VERILOG_DEFINE=[get_property verilog_define $fs]"
puts $fp "IMPL_STRATEGY=[get_property strategy $impl_run]"
puts $fp "FINAL_BIT=$final_bit"
puts $fp "BUILD_BIT=$build_bit"
puts $fp "TIMING_REPORT=$timing_rpt"
puts $fp "PATHS_REPORT=$paths_rpt"
puts $fp "CLOCKS_REPORT=$clocks_rpt"
puts $fp "CPU_CLOCK_PERIOD_NS=$clk_period"
puts $fp "CPU_CLOCK_FREQ_MHZ=$clk_freq"
puts $fp "WORST_SETUP_SLACK=$worst_slack"
puts $fp "WORST_SETUP_SOURCE=$worst_source"
puts $fp "WORST_SETUP_DESTINATION=$worst_dest"
close $fp

puts "FINAL_BIT=$final_bit"
puts "BUILD_BIT=$build_bit"
puts "TIMING_REPORT=$timing_rpt"
puts "PATHS_REPORT=$paths_rpt"
puts "CLOCKS_REPORT=$clocks_rpt"
puts "SUMMARY_TEXT=$summary_txt"
puts "CPU_CLOCK_PERIOD_NS=$clk_period"
puts "CPU_CLOCK_FREQ_MHZ=$clk_freq"
puts "WORST_SETUP_SLACK=$worst_slack"
puts "WORST_SETUP_SOURCE=$worst_source"
puts "WORST_SETUP_DESTINATION=$worst_dest"

close_project
