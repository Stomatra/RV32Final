if {[llength $argv] != 1} {
    puts "Usage: vivado -mode batch -source inspect_d_nets_after_place.tcl -tclargs <freq_mhz>"
    exit 1
}

set target_freq [lindex $argv 0]

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

set pll_ip [get_ips pll]
set pll_xci [get_files {d:/digital_twin/digital_twin/digital_twin.srcs/sources_1/ip/pll_1/pll.xci}]
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
cleanup_run_markers synth_1
reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
wait_for_checkpoint synth_1 top.dcp __synthesis_is_running__ 1800000

open_run synth_1
opt_design -directive Explore
place_design -directive ExtraPostPlacementOpt
write_checkpoint -force {d:/digital_twin/digital_twin/inspect_d_after_place.dcp}
report_high_fanout_nets -max_nets 100 -file {d:/digital_twin/digital_twin/inspect_high_fanout_after_place.rpt}

set out [open {d:/digital_twin/digital_twin/inspect_d_nets_after_place.txt} w]

set nets [lsort [get_nets -hier -regexp {^.*/student_top_inst/Core_cpu/D\[[0-9]+\]$}]]
puts $out [format {FOUND_NETS %d} [llength $nets]]
foreach net $nets {
    puts $out [format {NET %s} $net]
    set driver_pins [get_pins -leaf -of_objects $net -filter {DIRECTION == OUT}]
    foreach pin $driver_pins {
        set cell [get_cells -of_objects $pin]
        puts $out [format {  DRIVER_PIN %s} $pin]
        puts $out [format {  DRIVER_CELL %s} $cell]
        catch {puts $out [format {  DRIVER_REF %s} [get_property REF_NAME $cell]]}
    }
    set load_pins [lsort [get_pins -leaf -of_objects $net -filter {DIRECTION == IN}]]
    puts $out [format {  LOAD_COUNT %d} [llength $load_pins]]
    foreach pin [lrange $load_pins 0 59] {
        set cell [get_cells -of_objects $pin]
        puts $out [format {  LOAD_PIN %s} $pin]
        puts $out [format {  LOAD_CELL %s} $cell]
        catch {puts $out [format {  LOAD_REF %s} [get_property REF_NAME $cell]]}
    }
}

close $out

report_timing_summary -max_paths 10
close_design
close_project
exit
