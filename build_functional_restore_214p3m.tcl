set project_root [file normalize [pwd]]
set xpr [file join $project_root "digital_twin.xpr"]
set out_dir [file join $project_root "build_outputs"]
set final_dir [file join $project_root "final_bits"]
set stamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set build_tag "FUNCTIONAL_RESTORE_withmext_irom_v2_214p3m_${stamp}"
set build_bit [file join $out_dir "${build_tag}.build.bit"]
set final_bit [file join $final_dir "${build_tag}.bit"]
set stable_bit [file join $project_root "top_functional_restore_214p3m.bit"]
set root_top_bit [file join $project_root "top.bit"]
set timing_rpt [file join $out_dir "timing_${build_tag}.rpt"]
set paths_rpt [file join $out_dir "timing_paths_${build_tag}.rpt"]
set summary_txt [file join $out_dir "summary_${build_tag}.txt"]
set jobs 8
set target_freq_mhz 214.3

file mkdir $out_dir
file mkdir $final_dir

proc first_line {path} {
    set fp [open $path r]
    set line [gets $fp]
    close $fp
    return $line
}

proc run_has_error {run_name} {
    set status [get_property STATUS [get_runs $run_name]]
    puts "$run_name STATUS=$status"
    return [expr {[string first "ERROR" $status] >= 0}]
}

proc report_open_design {timing_rpt paths_rpt summary_txt final_bit build_bit stable_bit root_top_bit project_root target_freq_mhz build_tag} {
    report_timing_summary -max_paths 30 -report_unconstrained -file $timing_rpt -warn_on_violation
    report_timing -max_paths 30 -sort_by slack -file $paths_rpt

    set setup_path [get_timing_paths -setup -max_paths 1]
    set hold_path  [get_timing_paths -hold  -max_paths 1]
    set setup_slack "NA"
    set hold_slack "NA"
    if {[llength $setup_path] > 0} {
        set setup_slack [format %.3f [get_property SLACK [lindex $setup_path 0]]]
    }
    if {[llength $hold_path] > 0} {
        set hold_slack [format %.3f [get_property SLACK [lindex $hold_path 0]]]
    }

    write_bitstream -force $build_bit
    file copy -force $build_bit $final_bit
    file copy -force $build_bit $stable_bit
    file copy -force $build_bit $root_top_bit

    set fp [open $summary_txt w]
    puts $fp "BUILD_TAG=$build_tag"
    puts $fp "CPU_CLOCK_FREQ_MHZ=$target_freq_mhz"
    puts $fp "WORST_SETUP_SLACK=$setup_slack"
    puts $fp "WORST_HOLD_SLACK=$hold_slack"
    puts $fp "FINAL_BIT=$final_bit"
    puts $fp "BUILD_BIT=$build_bit"
    puts $fp "STABLE_BIT=$stable_bit"
    puts $fp "ROOT_TOP_BIT=$root_top_bit"
    puts $fp "TIMING_REPORT=$timing_rpt"
    puts $fp "PATHS_REPORT=$paths_rpt"
    close $fp

    puts "SUMMARY=$summary_txt"
    puts "FINAL_BIT=$final_bit"
    puts "STABLE_BIT=$stable_bit"
    puts "ROOT_TOP_BIT=$root_top_bit"
    puts "WORST_SETUP_SLACK=$setup_slack"
    puts "WORST_HOLD_SLACK=$hold_slack"
}

puts "OPEN_PROJECT=$xpr"
open_project $xpr

set fs [get_filesets sources_1]
set_property verilog_define {} $fs
set_property top top $fs
update_compile_order -fileset sources_1
puts "MYCPU_FILES=[get_files -of_objects $fs *myCPU.sv]"

set irom_ip [get_ips -quiet IROM]
if {[llength $irom_ip] == 0} {
    error "Cannot find IROM IP"
}
set irom_coe [file join $project_root "digital_twin.srcs" "sources_1" "imports" "test_src" "irom.coe"]
if {![file exists $irom_coe]} {
    error "Cannot find active IROM COE: $irom_coe"
}
puts "ACTIVE_IROM_COE=$irom_coe"
catch {set_property CONFIG.coefficient_file "../../imports/test_src/irom.coe" $irom_ip}

set pll_ips [get_ips -quiet pll]
if {[llength $pll_ips] == 0} {
    set pll_ips [get_ips -quiet *pll*]
}
if {[llength $pll_ips] == 0} {
    error "Cannot find PLL IP"
}
foreach pll_ip $pll_ips {
    puts "CONFIGURE_PLL=$pll_ip CLKOUT2=${target_freq_mhz}"
    set_property -dict [list CONFIG.PRIMITIVE {PLL} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 50.0 CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $target_freq_mhz] $pll_ip
}

puts "REGENERATE_IP_OUTPUT_PRODUCTS=[get_ips]"
generate_target all [get_ips] -force

set irom_mif [file join $project_root "digital_twin.gen" "sources_1" "ip" "IROM" "IROM.mif"]
set expected_first_irom_line "00000000000100100001000100010111"
if {![file exists $irom_mif]} {
    error "IROM.mif was not regenerated: $irom_mif"
}
set actual_first_irom_line [first_line $irom_mif]
puts "IROM_MIF_FIRST_LINE=$actual_first_irom_line"
if {$actual_first_irom_line ne $expected_first_irom_line} {
    error "IROM.mif does not match WithMext irom-v2 first word. Expected $expected_first_irom_line"
}

set ip_runs [get_runs -quiet *_synth_1]
if {[llength $ip_runs] > 0} {
    foreach r $ip_runs {
        catch {reset_run $r}
    }
    launch_runs $ip_runs -jobs $jobs
    foreach r $ip_runs {
        wait_on_run $r
        if {[run_has_error $r]} {
            error "$r failed"
        }
    }
}

catch {reset_run synth_1}
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[run_has_error synth_1]} {
    error "synth_1 failed"
}

set impl_run [get_runs impl_1]
set_property strategy Performance_Explore $impl_run
catch {set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $impl_run}
catch {set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraTimingOpt $impl_run}
catch {set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl_run}
catch {set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore $impl_run}

catch {reset_run impl_1}
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 STATUS=$impl_status"
if {[string first "ERROR" $impl_status] >= 0} {
    error "impl_1 errored: $impl_status"
}

open_run impl_1
report_open_design $timing_rpt $paths_rpt $summary_txt $final_bit $build_bit $stable_bit $root_top_bit $project_root $target_freq_mhz $build_tag

close_project
exit
