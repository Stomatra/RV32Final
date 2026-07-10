set origin_dir [file dirname [file normalize [info script]]]
set project_file [file join $origin_dir "digital_twin.xpr"]
set jobs 8
if {[info exists ::env(VIVADO_JOBS)] && $::env(VIVADO_JOBS) ne ""} {
    set jobs $::env(VIVADO_JOBS)
}
set reset_synth 1
if {[info exists ::env(VIVADO_RESET_SYNTH)] && $::env(VIVADO_RESET_SYNTH) ne ""} {
    set reset_synth $::env(VIVADO_RESET_SYNTH)
}

proc status_complete {run_name} {
    set run_obj [get_runs $run_name]
    set status [get_property STATUS $run_obj]
    set progress [get_property PROGRESS $run_obj]
    puts "$run_name STATUS=$status"
    puts "$run_name PROGRESS=$progress"
    if {$progress ne "100%"} {
        error "$run_name did not reach 100%"
    }
    if {![string match -nocase "*complete*" $status]} {
        error "$run_name did not complete: $status"
    }
}

proc path_pin_name {path prop fallback_prop} {
    if {[catch {set pin [get_property $prop $path]}] || $pin eq ""} {
        if {[catch {set pin [get_property $fallback_prop $path]}] || $pin eq ""} {
            return ""
        }
    }
    return [get_property NAME $pin]
}

open_project $project_file

set fileset [get_filesets sources_1]
set defines [get_property verilog_define $fileset]
puts "sources_1 verilog_define=$defines"
if {[string first "LED_WALK_TEST" $defines] >= 0} {
    error "LED_WALK_TEST is defined; refusing to build normal CPU bitstream."
}

update_compile_order -fileset sources_1

set impl_run [get_runs impl_1]
set_property strategy Performance_Explore $impl_run
puts "IMPL_STRATEGY=[get_property strategy $impl_run]"
foreach prop {
    STEPS.OPT_DESIGN.ARGS.DIRECTIVE
    STEPS.PLACE_DESIGN.ARGS.DIRECTIVE
    STEPS.PHYS_OPT_DESIGN.IS_ENABLED
    STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE
    STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE
} {
    catch {puts "$prop=[get_property $prop $impl_run]"}
}

# Vivado updates the .xpr when run properties change; close_project flushes the
# project cleanly in batch mode. There is no zero-argument save_project here.

if {$reset_synth} {
    puts "Resetting and launching synth_1 with current source files."
    reset_run synth_1
    launch_runs synth_1 -jobs $jobs
    wait_on_run synth_1
    status_complete synth_1
} else {
    puts "Skipping synth_1 reset by VIVADO_RESET_SYNTH=0."
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
status_complete impl_1

open_run impl_1
set timing_rpt [file join $origin_dir "timing_performance_explore_bit.rpt"]
set paths_rpt [file join $origin_dir "timing_performance_explore_bit_paths.rpt"]
set summary_txt [file join $origin_dir "timing_performance_explore_bit_summary.txt"]

report_timing_summary -max_paths 10 -report_unconstrained -warn_on_violation -file $timing_rpt
report_timing -delay_type max -max_paths 10 -sort_by group -file $paths_rpt

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

set fp [open $summary_txt w]
puts $fp "IMPL_STRATEGY=[get_property strategy $impl_run]"
puts $fp "TIMING_REPORT=$timing_rpt"
puts $fp "PATHS_REPORT=$paths_rpt"
puts $fp "WORST_SETUP_SLACK=$worst_slack"
puts $fp "WORST_SETUP_SOURCE=$worst_source"
puts $fp "WORST_SETUP_DESTINATION=$worst_dest"
close $fp

set run_bit [file join $origin_dir "digital_twin.runs" "impl_1" "top.bit"]
if {![file exists $run_bit]} {
    set bits [glob -nocomplain -directory [file join $origin_dir "digital_twin.runs" "impl_1"] *.bit]
    if {[llength $bits] == 0} {
        error "Implementation completed but no bitstream was found."
    }
    set run_bit [lindex $bits 0]
}

set stamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set named_bit [file join $origin_dir "top_performance_explore_${stamp}.bit"]
set stable_bit [file join $origin_dir "top_performance_explore.bit"]
file copy -force $run_bit $named_bit
file copy -force $run_bit $stable_bit

puts "TIMING_REPORT=$timing_rpt"
puts "PATHS_REPORT=$paths_rpt"
puts "SUMMARY_TEXT=$summary_txt"
puts "RUN_BIT=$run_bit"
puts "NAMED_BIT=$named_bit"
puts "STABLE_BIT=$stable_bit"
puts "WORST_SETUP_SLACK=$worst_slack"
puts "WORST_SETUP_SOURCE=$worst_source"
puts "WORST_SETUP_DESTINATION=$worst_dest"

close_project
