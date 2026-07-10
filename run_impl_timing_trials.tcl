set origin_dir [file dirname [file normalize [info script]]]
set project_file [file join $origin_dir "digital_twin.xpr"]
set out_dir $origin_dir
set jobs 8

proc fail_if_bad_run {run_name} {
    set status [get_property STATUS [get_runs $run_name]]
    puts "$run_name status=$status"
    if {[string match -nocase "*complete*" $status]} {
        return
    }
    if {[string match -nocase "*failed*" $status] ||
        [string match -nocase "*error*" $status] ||
        [string match -nocase "*cancel*" $status]} {
        error "$run_name failed: $status"
    }
}

proc try_set_run_property {run_obj prop value} {
    if {[catch {set_property $prop $value $run_obj} msg]} {
        puts "WARN: could not set $prop=$value: $msg"
        return 0
    }
    puts "SET $prop=[get_property $prop $run_obj]"
    return 1
}

proc report_current_timing {label timing_path paths_path} {
    open_run impl_1
    report_timing_summary -max_paths 10 -report_unconstrained -warn_on_violation -file $timing_path
    report_timing -delay_type max -max_paths 10 -sort_by group -file $paths_path
    puts "TIMING_REPORT_${label}: $timing_path"
    close_design
}

proc run_impl_trial {label timing_name paths_name configure_body} {
    global out_dir jobs
    set impl_run [get_runs impl_1]

    puts ""
    puts "========== TRIAL $label =========="
    uplevel 1 $configure_body

    puts "strategy=[get_property strategy $impl_run]"
    foreach prop {
        STEPS.OPT_DESIGN.ARGS.DIRECTIVE
        STEPS.PLACE_DESIGN.ARGS.DIRECTIVE
        STEPS.PHYS_OPT_DESIGN.IS_ENABLED
        STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE
        STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE
    } {
        catch {puts "$prop=[get_property $prop $impl_run]"}
    }

    reset_run impl_1
    launch_runs impl_1 -to_step route_design -jobs $jobs
    wait_on_run impl_1
    fail_if_bad_run impl_1

    report_current_timing $label [file join $out_dir $timing_name] [file join $out_dir $paths_name]
}

open_project $project_file

set fileset [get_filesets sources_1]
puts "sources_1 verilog_define=[get_property verilog_define $fileset]"
if {[string first "LED_WALK_TEST" [get_property verilog_define $fileset]] >= 0} {
    error "LED_WALK_TEST is still defined; refusing to run normal CPU timing trials."
}

set impl_run [get_runs impl_1]
set original_strategy [get_property strategy $impl_run]
array set original_props {}
foreach prop {
    STEPS.OPT_DESIGN.ARGS.DIRECTIVE
    STEPS.PLACE_DESIGN.ARGS.DIRECTIVE
    STEPS.PHYS_OPT_DESIGN.IS_ENABLED
    STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE
    STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE
} {
    catch {set original_props($prop) [get_property $prop $impl_run]}
}

run_impl_trial "RETRY" "timing_retry.rpt" "timing_retry_paths.rpt" {
    # Baseline retry: keep the run settings as opened, only reset impl_1.
}

run_impl_trial "PHYS_OPT" "timing_phys_opt.rpt" "timing_phys_opt_paths.rpt" {
    try_set_run_property $impl_run STEPS.PHYS_OPT_DESIGN.IS_ENABLED true
    try_set_run_property $impl_run STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore
}

run_impl_trial "PERFORMANCE_EXPLORE" "timing_performance_explore.rpt" "timing_performance_explore_paths.rpt" {
    try_set_run_property $impl_run strategy Performance_Explore
}

run_impl_trial "PERFORMANCE_EXTRA_TIMING_OPT" "timing_performance_extra_timing_opt.rpt" "timing_performance_extra_timing_opt_paths.rpt" {
    try_set_run_property $impl_run strategy Performance_ExtraTimingOpt
}

# Leave the project run properties as they were when the script started.
set_property strategy $original_strategy $impl_run
foreach prop [array names original_props] {
    catch {set_property $prop $original_props($prop) $impl_run}
}

close_project
