set origin_dir [file dirname [file normalize [info script]]]
set project_file [file join $origin_dir "digital_twin.xpr"]
set jobs 8
if {[info exists ::env(VIVADO_JOBS)] && $::env(VIVADO_JOBS) ne ""} {
    set jobs $::env(VIVADO_JOBS)
}

set bit_name "top_withoutmext_150m_normal_rebuild.bit"
if {[info exists ::env(NORMAL_REBUILD_BIT_NAME)] && $::env(NORMAL_REBUILD_BIT_NAME) ne ""} {
    set bit_name $::env(NORMAL_REBUILD_BIT_NAME)
}
set report_prefix "withoutmext_150m_normal_rebuild"
if {[info exists ::env(NORMAL_REBUILD_REPORT_PREFIX)] && $::env(NORMAL_REBUILD_REPORT_PREFIX) ne ""} {
    set report_prefix $::env(NORMAL_REBUILD_REPORT_PREFIX)
}

set bit_out [file join $origin_dir $bit_name]
set timing_rpt [file join $origin_dir "timing_${report_prefix}.rpt"]
set paths_rpt [file join $origin_dir "timing_${report_prefix}_paths.rpt"]
set summary_txt [file join $origin_dir "timing_${report_prefix}_summary.txt"]
set irom_coe [file join $origin_dir "digital_twin.srcs" "sources_1" "imports" "test_src" "irom.coe"]
set irom_xci [file join $origin_dir "digital_twin.srcs" "sources_1" "ip" "IROM" "IROM.xci"]
set irom_mif [file join $origin_dir "digital_twin.gen" "sources_1" "ip" "IROM" "IROM.mif"]

proc status_complete {run_name} {
    set run_obj [get_runs $run_name]
    set status [get_property STATUS $run_obj]
    set progress [get_property PROGRESS $run_obj]
    puts "$run_name STATUS=$status"
    puts "$run_name PROGRESS=$progress"
    if {$progress ne "100%"} {
        error "$run_name did not reach 100%"
    }
    if {![string match -nocase "*complete*" $status] &&
        ![string match -nocase "*cached IP results*" $status]} {
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

proc remove_debug_defines {defines} {
    set filtered {}
    foreach define $defines {
        if {$define ne "DEBUG_HW_MILESTONE" && $define ne "LED_WALK_TEST"} {
            lappend filtered $define
        }
    }
    return $filtered
}

foreach required [list $project_file $irom_coe $irom_xci] {
    if {![file exists $required]} {
        error "Required file not found: $required"
    }
}

open_project $project_file

set sources_fs [get_filesets sources_1]
set original_defines [get_property verilog_define $sources_fs]
set normal_defines [remove_debug_defines $original_defines]
set_property verilog_define $normal_defines $sources_fs
set current_defines [get_property verilog_define $sources_fs]
puts "ORIGINAL_VERILOG_DEFINE=$original_defines"
puts "CURRENT_VERILOG_DEFINE=$current_defines"
if {[string first "DEBUG_HW_MILESTONE" $current_defines] >= 0} {
    error "DEBUG_HW_MILESTONE remains in sources_1 verilog_define."
}
if {[string first "LED_WALK_TEST" $current_defines] >= 0} {
    error "LED_WALK_TEST remains in sources_1 verilog_define."
}

set irom_ip [get_files -quiet [file normalize $irom_xci]]
if {[llength $irom_ip] == 0} {
    error "IROM IP is not part of the project: $irom_xci"
}

puts "IROM_COE=$irom_coe"
puts "IROM_XCI=$irom_xci"
if {[file exists $irom_mif]} {
    file delete -force $irom_mif
}
generate_target all $irom_ip -force
if {![file exists $irom_mif]} {
    error "IROM.mif was not regenerated: $irom_mif"
}
puts "IROM_MIF_REGENERATED=$irom_mif"

if {[llength [get_runs -quiet IROM_synth_1]] > 0} {
    puts "Resetting and launching IROM_synth_1."
    reset_run IROM_synth_1
    launch_runs IROM_synth_1 -jobs $jobs
    wait_on_run IROM_synth_1
    status_complete IROM_synth_1
}

update_compile_order -fileset sources_1

set impl_run [get_runs impl_1]
set_property strategy Performance_Explore $impl_run
puts "IMPL_STRATEGY=[get_property strategy $impl_run]"

puts "Resetting and launching synth_1."
reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
status_complete synth_1

puts "Resetting and launching impl_1 through write_bitstream."
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
status_complete impl_1

open_run impl_1
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

set run_bit [file join $origin_dir "digital_twin.runs" "impl_1" "top.bit"]
if {![file exists $run_bit]} {
    set bits [glob -nocomplain -directory [file join $origin_dir "digital_twin.runs" "impl_1"] *.bit]
    if {[llength $bits] == 0} {
        error "Implementation completed but no bitstream was found."
    }
    set run_bit [lindex $bits 0]
}
file copy -force $run_bit $bit_out

set fp [open $summary_txt w]
puts $fp "BIT=$bit_out"
puts $fp "TIMING_REPORT=$timing_rpt"
puts $fp "PATHS_REPORT=$paths_rpt"
puts $fp "ORIGINAL_VERILOG_DEFINE=$original_defines"
puts $fp "CURRENT_VERILOG_DEFINE=$current_defines"
puts $fp "IROM_COE=$irom_coe"
puts $fp "IROM_MIF=$irom_mif"
puts $fp "IMPL_STRATEGY=[get_property strategy $impl_run]"
puts $fp "WORST_SETUP_SLACK=$worst_slack"
puts $fp "WORST_SETUP_SOURCE=$worst_source"
puts $fp "WORST_SETUP_DESTINATION=$worst_dest"
close $fp

puts "BIT=$bit_out"
puts "TIMING_REPORT=$timing_rpt"
puts "PATHS_REPORT=$paths_rpt"
puts "SUMMARY_TEXT=$summary_txt"
puts "WORST_SETUP_SLACK=$worst_slack"
puts "WORST_SETUP_SOURCE=$worst_source"
puts "WORST_SETUP_DESTINATION=$worst_dest"

close_project
