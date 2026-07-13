set origin_dir [file normalize [pwd]]
set project_file [file join $origin_dir "digital_twin.xpr"]

if {![file exists $project_file]} {
    error "Cannot find project: $project_file"
}

proc run_status_ok {run_name} {
    set run_obj [get_runs $run_name]
    set status [get_property STATUS $run_obj]
    set progress [get_property PROGRESS $run_obj]
    puts "$run_name STATUS: $status"
    puts "$run_name PROGRESS: $progress"
    if {$progress ne "100%"} {
        error "$run_name did not complete"
    }
    if {[string match -nocase "*failed*" $status] ||
        [string match -nocase "*error*" $status] ||
        [string match -nocase "*aborted*" $status]} {
        error "$run_name failed: $status"
    }
}

proc try_set_run_property {run_obj prop value} {
    if {[catch {set_property $prop $value $run_obj} msg]} {
        puts "WARN: could not set $prop=$value: $msg"
    } else {
        puts "Set $prop=$value"
    }
}

proc worst_setup_slack {} {
    set paths [get_timing_paths -setup -max_paths 1 -nworst 1]
    if {[llength $paths] == 0} {
        return 999.0
    }
    return [get_property SLACK [lindex $paths 0]]
}

open_project $project_file

set fileset [get_filesets sources_1]
# Keep the PLL XCI as the source of truth. Generated HDL files may appear as IP
# children in get_files, but they should not be manually added as top-level HDL
# entries in digital_twin.xpr.

set uart_rx_file [file join $origin_dir "digital_twin.srcs" "sources_1" "new" "uart_rx.sv"]
if {[file exists $uart_rx_file] && [llength [get_files -quiet -of_objects $fileset $uart_rx_file]] == 0} {
    add_files -norecurse -fileset sources_1 $uart_rx_file
    set_property file_type SystemVerilog [get_files $uart_rx_file]
    puts "ADDED_UART_RX_SOURCE=$uart_rx_file"
}

set pll_xci [get_files -quiet -of_objects $fileset "*/sources_1/ip/pll_1/pll.xci"]
if {[llength $pll_xci] == 0} {
    set pll_xci [get_files -quiet -of_objects $fileset "*/sources_1/ip/pll/pll.xci"]
}
if {[llength $pll_xci] == 0} {
    error "Cannot find PLL XCI in sources_1"
}
puts "Using PLL IP: [lindex $pll_xci 0]"

set ip_objs [get_ips -quiet -of_objects $pll_xci]
if {[llength $ip_objs] > 0} {
    set locked_ips [get_ips -quiet -filter {IS_LOCKED == 1}]
    if {[llength $locked_ips] > 0} {
        puts "Upgrading locked IP if needed: $locked_ips"
        upgrade_ip $locked_ips
    }
}

reset_target all $pll_xci
generate_target all $pll_xci
export_ip_user_files -of_objects $pll_xci -no_script -sync -force -quiet

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set synth_run [get_runs synth_1]
set impl_run [get_runs impl_1]

try_set_run_property $synth_run "strategy" "Flow_PerfOptimized_high"
try_set_run_property $impl_run "STEPS.OPT_DESIGN.ARGS.DIRECTIVE" "Explore"
try_set_run_property $impl_run "STEPS.PLACE_DESIGN.ARGS.DIRECTIVE" "Explore"
try_set_run_property $impl_run "STEPS.PHYS_OPT_DESIGN.IS_ENABLED" true
try_set_run_property $impl_run "STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE" "AggressiveExplore"
try_set_run_property $impl_run "STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE" "HigherDelayCost"

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
run_status_ok synth_1

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
run_status_ok impl_1

open_run impl_1
report_timing_summary -file [file join $origin_dir "top_timing_summary_normal.rpt"] -warn_on_violation
report_utilization -file [file join $origin_dir "top_utilization_normal.rpt"]
set routed_wns [worst_setup_slack]
puts "NORMAL_ROUTED_WNS: $routed_wns"

set bit_file [file join $origin_dir "digital_twin.runs" "impl_1" "top.bit"]
if {![file exists $bit_file]} {
    set bit_candidates [glob -nocomplain -directory [file join $origin_dir "digital_twin.runs" "impl_1"] *.bit]
    if {[llength $bit_candidates] == 0} {
        error "Implementation completed, but no bitstream was found in impl_1"
    }
    set bit_file [lindex $bit_candidates 0]
}

if {$routed_wns < 0.0} {
    puts "Running post-route phys_opt cleanup because routed WNS is negative."
    if {[catch {phys_opt_design -directive AggressiveExplore} phys_msg]} {
        puts "WARN: post-route phys_opt failed: $phys_msg"
    } elseif {[catch {route_design -directive HigherDelayCost} route_msg]} {
        puts "WARN: post-route route cleanup failed: $route_msg"
    } else {
        report_timing_summary -file [file join $origin_dir "top_timing_summary_postroute_physopt.rpt"] -warn_on_violation
        set cleanup_wns [worst_setup_slack]
        puts "POSTROUTE_PHYSOPT_WNS: $cleanup_wns"
        write_checkpoint -force [file join $origin_dir "top_postroute_physopt.dcp"]
        set clean_bit [file join $origin_dir "top_normal_timing_clean.bit"]
        write_bitstream -force $clean_bit
        if {$cleanup_wns > $routed_wns} {
            set bit_file $clean_bit
        }
    }
}

file copy -force $bit_file [file join $origin_dir "top_normal.bit"]
puts "BITSTREAM: $bit_file"
puts "COPIED_BITSTREAM: [file join $origin_dir "top_normal.bit"]"
