set root_dir [file normalize "."]
set target_freqs {200.0 202.25}
set out_dir [file join $root_dir "timing_backups" "freq_probe_explore_dual_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"]
file mkdir $out_dir
set summary_path [file join $out_dir "summary.tsv"]
set summary_chan [open $summary_path w]
puts $summary_chan "freq_mhz\twns\tstatus\treport\tdcp"

proc cleanup_run_markers {run_dir} {
    foreach pattern {.stop.rst .vivado.begin.rst .vivado.end.rst .vivado.error.rst __synthesis_is_running__ __implementation_is_running__} {
        foreach stale_file [glob -nocomplain -directory $run_dir $pattern] {
            catch {file delete -force $stale_file}
        }
    }
}

proc sanitize_freq_tag {freq} {
    return [regsub -all {\.} $freq {p}]
}

open_project [file join $root_dir "digital_twin.xpr"]
set srcset [get_filesets sources_1]
catch {
    set old_import_mycpu [get_files -of_objects $srcset [file join $root_dir "digital_twin.srcs" "sources_1" "imports" "new" "myCPU.sv"]]
    if {[llength $old_import_mycpu] > 0} {
        remove_files $old_import_mycpu
    }
}
set mycpu_file_new [get_files -of_objects $srcset [file join $root_dir "digital_twin.srcs" "sources_1" "new" "myCPU.sv"]]
if {[llength $mycpu_file_new] == 0} {
    add_files -fileset $srcset -norecurse [file join $root_dir "digital_twin.srcs" "sources_1" "new" "myCPU.sv"]
    set mycpu_file_new [get_files -of_objects $srcset [file join $root_dir "digital_twin.srcs" "sources_1" "new" "myCPU.sv"]]
}
if {[llength $mycpu_file_new] == 1} {
    catch {set_property FILE_TYPE SystemVerilog $mycpu_file_new}
    catch {set_property IS_ENABLED true $mycpu_file_new}
    catch {set_property USED_IN_SYNTHESIS true $mycpu_file_new}
    catch {set_property USED_IN_IMPLEMENTATION true $mycpu_file_new}
}
update_compile_order -fileset sources_1

set pll_ip [get_ips pll]
set pll_xci [get_files [file join $root_dir "digital_twin.srcs" "sources_1" "ip" "pll_1" "pll.xci"]]
if {[llength $pll_ip] != 1 || [llength $pll_xci] != 1} {
    puts "ERROR: Could not resolve pll IP or pll_1 xci"
    close $summary_chan
    close_project
    exit 1
}

foreach freq $target_freqs {
    set tag [sanitize_freq_tag $freq]
    set status ok
    set wns NA
    set report_path [file join $out_dir "timing_${tag}.rpt"]
    set dcp_path [file join $out_dir "top_${tag}.dcp"]
    puts "===== EXPLORE PROBE $freq MHz ====="

    if {[catch {
        upgrade_ip $pll_ip
        set_property -dict [list CONFIG.PRIMITIVE {PLL} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 50.0 CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $freq] $pll_ip
        reset_target all $pll_xci
        generate_target all $pll_xci
        export_ip_user_files -of_objects $pll_xci -no_script -sync -force -quiet

        if {[llength [get_runs pll_synth_1]] == 0} {
            create_ip_run $pll_xci
        }
        cleanup_run_markers [file normalize [file join $root_dir "digital_twin.runs" "pll_synth_1"]]
        reset_run pll_synth_1
        launch_runs pll_synth_1 -jobs 2
        wait_on_run pll_synth_1

        update_compile_order -fileset sources_1
        cleanup_run_markers [file normalize [file join $root_dir "digital_twin.runs" "synth_1"]]
        reset_run synth_1
        launch_runs synth_1 -jobs 2
        wait_on_run synth_1
        open_run synth_1

        opt_design
        place_design -directive Explore
        phys_opt_design
        route_design -timing_summary

        set worst_path [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
        if {$worst_path ne ""} {
            set wns [get_property SLACK $worst_path]
        }
        report_timing_summary -max_paths 10 -report_unconstrained -file $report_path
        write_checkpoint -force $dcp_path
        close_design
    } err]} {
        set status $err
        catch {close_design}
    }

    puts $summary_chan [format "%s\t%s\t%s\t%s\t%s" $freq $wns $status $report_path $dcp_path]
    flush $summary_chan
}

upgrade_ip $pll_ip
set_property -dict [list CONFIG.PRIMITIVE {PLL} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 50.0 CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 200.0] $pll_ip
reset_target all $pll_xci
generate_target all $pll_xci
export_ip_user_files -of_objects $pll_xci -no_script -sync -force -quiet

close $summary_chan
puts "SUMMARY_FILE=$summary_path"
puts "OUTPUT_DIR=$out_dir"
close_project
exit
