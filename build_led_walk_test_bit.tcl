set origin_dir [file normalize [pwd]]
set project_file [file join $origin_dir "digital_twin.xpr"]
set output_bit [file join $origin_dir "top_led_walk32_uart_ok.bit"]
set output_timing [file join $origin_dir "top_timing_summary_led_walk32_uart_ok.rpt"]
set output_util [file join $origin_dir "top_utilization_led_walk32_uart_ok.rpt"]

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

proc append_define {defines define_name} {
    set result {}
    foreach item $defines {
        if {$item ne "" && [lsearch -exact $result $item] < 0} {
            lappend result $item
        }
    }
    if {[lsearch -exact $result $define_name] < 0} {
        lappend result $define_name
    }
    return $result
}

proc remove_define {defines define_name} {
    set result {}
    foreach item $defines {
        if {$item ne "" && $item ne $define_name && [lsearch -exact $result $item] < 0} {
            lappend result $item
        }
    }
    return $result
}

proc restore_defines {fileset defines} {
    if {[llength $defines] == 0} {
        set_property verilog_define {} $fileset
    } else {
        set_property verilog_define $defines $fileset
    }
    puts "Restored sources_1 verilog_define=[get_property verilog_define $fileset]"
}

open_project $project_file

set fileset [get_filesets sources_1]
set old_defines [get_property verilog_define $fileset]
set restore_defines [remove_define $old_defines LED_WALK_TEST]

set build_code [catch {
    set_property verilog_define [append_define $restore_defines LED_WALK_TEST] $fileset
    puts "Temporary sources_1 verilog_define=[get_property verilog_define $fileset]"

    set pll_xci_path [file join $origin_dir "digital_twin.srcs" "sources_1" "ip" "pll_1" "pll.xci"]
    if {![file exists $pll_xci_path]} {
        set pll_xci_path [file join $origin_dir "digital_twin.srcs" "sources_1" "ip" "pll" "pll.xci"]
    }
    set pll_xci [get_files -quiet $pll_xci_path]
    if {[llength $pll_xci] == 0} {
        error "Cannot find PLL XCI in sources_1 at $pll_xci_path"
    }
    generate_target all $pll_xci
    export_ip_user_files -of_objects $pll_xci -no_script -sync -force -quiet

    update_compile_order -fileset sources_1

    reset_run synth_1
    launch_runs synth_1 -jobs 8
    wait_on_run synth_1
    run_status_ok synth_1

    reset_run impl_1
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1
    run_status_ok impl_1

    open_run impl_1
    report_timing_summary -file $output_timing -warn_on_violation
    report_utilization -file $output_util

    set run_bit [file join $origin_dir "digital_twin.runs" "impl_1" "top.bit"]
    if {![file exists $run_bit]} {
        error "Implementation completed, but $run_bit was not found"
    }
    file copy -force $run_bit $output_bit
    puts "LED_WALK32_UART_OK_BITSTREAM: $output_bit"
} build_result build_options]

restore_defines $fileset $restore_defines

if {$build_code != 0} {
    return -options $build_options $build_result
}
