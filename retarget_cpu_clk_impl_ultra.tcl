if {[llength $argv] != 1} {
    puts "Usage: vivado -mode batch -source retarget_cpu_clk_impl_ultra.tcl -tclargs <freq_mhz>"
    exit 1
}

set target_freq [lindex $argv 0]
set freq_tag [regsub -all {\.} $target_freq {p}]

proc cleanup_run_markers {run_name} {
    set run_dir [file normalize [format {d:/digital_twin/digital_twin/digital_twin.runs/%s} $run_name]]
    foreach pattern {
        .stop.rst
        .vivado.begin.rst
        .vivado.end.rst
        .vivado.error.rst
        __synthesis_is_running__
        __implementation_is_running__
    } {
        foreach stale_file [glob -nocomplain -directory $run_dir $pattern] {
            catch {file delete -force $stale_file}
        }
    }
}

proc wait_for_checkpoint {run_name checkpoint_name running_marker timeout_ms} {
    set run_dir [file normalize [format {d:/digital_twin/digital_twin/digital_twin.runs/%s} $run_name]]
    set checkpoint_path [file join $run_dir $checkpoint_name]
    set running_path [file join $run_dir $running_marker]
    set deadline [expr {[clock milliseconds] + $timeout_ms}]

    while {1} {
        if {[file exists $checkpoint_path] && ![file exists $running_path]} {
            return
        }
        if {[clock milliseconds] >= $deadline} {
            error [format {Timed out waiting for %s/%s to complete} $run_name $checkpoint_name]
        }
        after 1000
    }
}

open_project {d:/digital_twin/digital_twin/digital_twin.xpr}

# Force-enable myCPU source and keep only the canonical path under sources_1/new.
set srcset [get_filesets sources_1]
catch {
    set old_import_mycpu [get_files -of_objects $srcset {d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/imports/new/myCPU.sv}]
    if {[llength $old_import_mycpu] > 0} {
        remove_files $old_import_mycpu
    }
}

set mycpu_file_new [get_files -of_objects $srcset {d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/new/myCPU.sv}]
if {[llength $mycpu_file_new] == 0} {
    add_files -fileset $srcset -norecurse {d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/new/myCPU.sv}
    set mycpu_file_new [get_files -of_objects $srcset {d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/new/myCPU.sv}]
}
if {[llength $mycpu_file_new] == 1} {
    catch {set_property FILE_TYPE SystemVerilog $mycpu_file_new}
    catch {set_property IS_ENABLED true $mycpu_file_new}
    catch {set_property USED_IN_SYNTHESIS true $mycpu_file_new}
    catch {set_property USED_IN_IMPLEMENTATION true $mycpu_file_new}
    catch {set_property USED_IN_SIMULATION true $mycpu_file_new}
}

update_compile_order -fileset sources_1

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

cleanup_run_markers pll_synth_1
reset_run pll_synth_1
launch_runs pll_synth_1 -jobs 2
wait_on_run pll_synth_1

update_compile_order -fileset sources_1

if {[llength [get_runs synth_1]] == 0} {
    create_run -name synth_1 -part xc7k325tffg900-2 -flow {Vivado Synthesis 2023} -strategy Vivado Synthesis Defaults -constrset constrs_1
}

cleanup_run_markers synth_1
reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
open_run synth_1

# A more timing-focused hand-crafted flow used only after default/aggressive miss.
opt_design -directive Explore
place_design -directive ExtraPostPlacementOpt
phys_opt_design -directive AggressiveExplore
route_design -directive Explore

set post_route_path [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
if {[llength $post_route_path] > 0} {
    set post_route_wns [get_property SLACK $post_route_path]
} else {
    set post_route_wns -999.0
}
puts [format {INFO: route WNS before post-route phys_opt = %.3f} $post_route_wns]

if {$post_route_wns > -2.0} {
    phys_opt_design -directive Default
    route_design -directive Explore

    set post_route_path2 [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
    if {[llength $post_route_path2] > 0} {
        set post_route_wns2 [get_property SLACK $post_route_path2]
    } else {
        set post_route_wns2 -999.0
    }
    puts [format {INFO: route WNS before second post-route phys_opt = %.3f} $post_route_wns2]

    if {$post_route_wns2 > -2.0} {
        phys_opt_design -directive Default
    } else {
        puts "INFO: Skip second post-route phys_opt due to poor WNS"
    }
} else {
    puts "INFO: Skip post-route phys_opt due to poor WNS"
}

report_clocks -file [format {d:/digital_twin/digital_twin/openrun_impl_clocks_ultra_%sm.rpt} $freq_tag]
report_timing_summary -max_paths 30 -file [format {d:/digital_twin/digital_twin/openrun_top_timing_impl_ultra_%sm.rpt} $freq_tag]
report_utilization -file [format {d:/digital_twin/digital_twin/openrun_top_utilization_impl_ultra_%sm.rpt} $freq_tag]

close_design
close_project
exit
