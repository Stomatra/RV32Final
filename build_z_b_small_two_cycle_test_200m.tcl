set project_root [file normalize [pwd]]
set xpr [file join $project_root "digital_twin.xpr"]
set out_dir [file join $project_root "z_b_small_two_cycle_build_outputs"]
set final_dir [file join $project_root "final_bits"]
set stamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set build_tag "Z_B_SMALL_TWO_CYCLE_TEST_200MHz_${stamp}"

set root_bit [file join $project_root "Z_B_SMALL_TWO_CYCLE_TEST_200MHz.bit"]
set final_bit [file join $final_dir "${build_tag}.bit"]
set summary_txt [file join $out_dir "summary_${build_tag}.txt"]
set timing_rpt [file join $out_dir "timing_${build_tag}.rpt"]
set timing_paths_rpt [file join $out_dir "timing_paths_top3_${build_tag}.rpt"]
set drc_rpt [file join $out_dir "drc_${build_tag}.rpt"]
set compile_order_rpt [file join $out_dir "compile_order_${build_tag}.txt"]

set jobs 8
set top_module "top"
set target_freq_mhz 200.000

set source_irom [file join $project_root "digital_twin.srcs" "sources_1" "imports" "test_src" "irom-z-b-small-test.coe"]
set source_dram [file join $project_root "digital_twin.srcs" "file_coe" "coe" "withMext" "demo" "dram.coe"]
set active_irom [file join $project_root "digital_twin.srcs" "sources_1" "imports" "test_src" "irom.coe"]
set active_dram [file join $project_root "digital_twin.srcs" "sources_1" "imports" "test_src" "dram.coe"]
set main_xdc [file join $project_root "digital_twin.srcs" "constrs_1" "new" "digital_twin.xdc"]
set mycpu_sv [file join $project_root "digital_twin.srcs" "sources_1" "new" "myCPU.sv"]
set old_mycpu_sv [file join $project_root "digital_twin.srcs" "sources_1" "imports" "new" "myCPU.sv"]
set perip_bridge_sv [file join $project_root "digital_twin.srcs" "sources_1" "new" "perip_bridge.sv"]
set student_top_sv [file join $project_root "digital_twin.srcs" "sources_1" "new" "student_top.sv"]
set z_decode_sv [file join $project_root "digital_twin.srcs" "sources_1" "new" "z_light_decode.sv"]
set z_unit_sv [file join $project_root "digital_twin.srcs" "sources_1" "imports" "new" "z_light_unit.sv"]
set divider_sv [file join $project_root "digital_twin.srcs" "sources_1" "imports" "new" "Divider.sv"]
set pll_xci [file join $project_root "digital_twin.srcs" "sources_1" "ip" "pll_1" "pll.xci"]
set irom_bram_xci [file join $project_root "digital_twin.srcs" "sources_1" "ip" "IROM_BRAM" "IROM_BRAM.xci"]

file mkdir $out_dir
file mkdir $final_dir

proc sha256_file {path} {
    set output [exec certutil -hashfile [file normalize $path] SHA256]
    foreach line [split $output "\n"] {
        set trimmed [string trim $line]
        if {[regexp {^[0-9A-Fa-f]{64}$} $trimmed]} {
            return [string toupper $trimmed]
        }
    }
    error "Cannot parse SHA256 for $path"
}

proc parse_timing_summary_values {rpt} {
    if {![file exists $rpt]} { return [list "" "" ""] }
    set fp [open $rpt r]
    set text [read $fp]
    close $fp
    foreach line [split $text "\n"] {
        if {[regexp {^\s*(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+[0-9]+\s+[0-9]+\s+(-?[0-9]+\.[0-9]+)\s+} $line -> wns tns whs]} {
            return [list $wns $tns $whs]
        }
    }
    return [list "" "" ""]
}

proc drc_report_error_count {rpt} {
    if {![file exists $rpt]} { return -1 }
    set fp [open $rpt r]
    set text [read $fp]
    close $fp
    set count 0
    foreach line [split $text "\n"] {
        if {[regexp {\|\s+[A-Za-z0-9_-]+\s+\|\s+Error\s+\|.*\|\s+([0-9]+)\s+\|} $line -> n]} {
            incr count $n
        }
    }
    return $count
}

proc report_has {rpt pattern} {
    if {![file exists $rpt]} { return 0 }
    set fp [open $rpt r]
    set text [read $fp]
    close $fp
    return [expr {[string first $pattern $text] >= 0}]
}

proc copy_checked {src dst} {
    if {![file exists $src]} { error "Missing source $src" }
    file mkdir [file dirname $dst]
    file copy -force $src $dst
}

puts "BUILD_TAG=$build_tag"
puts "RESUME_EXISTING_ROUTE=0"
puts "OPEN_CHECKPOINT_USED=0"
puts "ENABLE_Z_B_SMALL=1"

copy_checked $source_irom $active_irom
copy_checked $source_dram $active_dram

set irom_sha [sha256_file $active_irom]
set dram_sha [sha256_file $active_dram]
puts "ACTIVE_IROM_SHA256=$irom_sha"
puts "ACTIVE_DRAM_SHA256=$dram_sha"

open_project $xpr

set fs [get_filesets sources_1]
set_property top $top_module $fs
set_property verilog_define {ENABLE_Z_B_SMALL} $fs
set_property generic {} $fs

set old_file [get_files -quiet [file normalize $old_mycpu_sv]]
if {[llength $old_file] > 0} {
    remove_files $old_file
}

set needed_files [list $mycpu_sv $z_decode_sv $z_unit_sv $divider_sv]
foreach f $needed_files {
    if {![file exists $f]} { error "Missing required source $f" }
    if {[llength [get_files -quiet [file normalize $f]]] == 0} {
        add_files -fileset sources_1 $f
    }
}
foreach f $needed_files {
    set gf [get_files -quiet [file normalize $f]]
    if {[llength $gf] > 0} {
        set_property file_type SystemVerilog $gf
    }
}

if {![file exists $irom_bram_xci]} {
    error "Missing restored IROM_BRAM IP file $irom_bram_xci"
}
if {[llength [get_files -quiet [file normalize $irom_bram_xci]]] == 0} {
    add_files -fileset sources_1 $irom_bram_xci
}

set constrs [get_filesets constrs_1]
set enabled_xdcs {}
foreach cf [get_files -of_objects $constrs] {
    if {[string tolower [file extension $cf]] eq ".xdc"} {
        set used [expr {[file normalize $cf] eq [file normalize $main_xdc]}]
        set_property IS_ENABLED $used $cf
        if {$used} { lappend enabled_xdcs [file normalize $cf] }
    }
}

set irom_ip [get_ips -quiet IROM]
set dram_ip [get_ips -quiet DRAM]
set pll_ip [get_ips -quiet pll]
set irom_bram_ip [get_ips -quiet IROM_BRAM]
if {[llength $irom_ip] == 0} { error "Cannot find IROM IP" }
if {[llength $dram_ip] == 0} { error "Cannot find DRAM IP" }
if {[llength $pll_ip] == 0} { error "Cannot find pll IP" }
if {[llength $irom_bram_ip] == 0} { error "Cannot find IROM_BRAM IP" }

foreach ip [list $irom_ip $dram_ip $pll_ip $irom_bram_ip] {
    set locked 0
    catch {set locked [get_property IS_LOCKED $ip]}
    if {$locked} {
        upgrade_ip $ip
    }
}

set irom_ip [get_ips -quiet IROM]
set dram_ip [get_ips -quiet DRAM]
set pll_ip [get_ips -quiet pll]
set irom_bram_ip [get_ips -quiet IROM_BRAM]

catch {reset_target all $pll_ip}
set_property -dict [list \
    CONFIG.PRIMITIVE {PLL} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $target_freq_mhz \
] $pll_ip

generate_target all $irom_ip -force
puts "IROM_IP_REFRESHED=1"
generate_target all $irom_bram_ip -force
puts "IROM_BRAM_IP_REFRESHED=1"
generate_target all $dram_ip -force
puts "DRAM_IP_REFRESHED=1"
generate_target all $pll_ip -force
puts "PLL_IP_REFRESHED=1"
export_ip_user_files -of_objects [list $irom_ip $irom_bram_ip $dram_ip $pll_ip] -no_script -sync -force -quiet
update_compile_order -fileset sources_1

set co_fp [open $compile_order_rpt w]
puts $co_fp "SOURCE_COMPILE_ORDER"
foreach f [get_files -compile_order sources -used_in synthesis] {
    puts $co_fp $f
}
close $co_fp

set ip_runs [get_runs -quiet *_synth_1]
foreach r $ip_runs { catch {reset_run $r} }
if {[llength $ip_runs] > 0} {
    launch_runs $ip_runs -jobs $jobs
    foreach r $ip_runs { wait_on_run $r }
}

set synth_run [get_runs synth_1]
set impl_run [get_runs impl_1]
set_property strategy "Vivado Synthesis Defaults" $synth_run
set_property strategy "Performance_Explore" $impl_run
catch {set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $impl_run}
catch {set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl_run}
catch {set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore $impl_run}
catch {set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true $impl_run}
catch {set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl_run}

puts "RESET_RUN_SYNTH_1=1"
reset_run synth_1
puts "RESET_RUN_IMPL_1=1"
reset_run impl_1

puts "LAUNCH_SYNTH_1"
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
puts "LAUNCH_IMPL_1_WRITE_BITSTREAM"
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1

open_run impl_1
report_timing_summary -max_paths 10 -report_unconstrained -file $timing_rpt
report_timing -setup -max_paths 3 -sort_by group -file $timing_paths_rpt
report_drc -file $drc_rpt

set timing_vals [parse_timing_summary_values $timing_rpt]
set wns [lindex $timing_vals 0]
set tns [lindex $timing_vals 1]
set whs [lindex $timing_vals 2]
set drc_error_count [drc_report_error_count $drc_rpt]
set has_bivc [report_has $drc_rpt "BIVC"]
set has_nstd [report_has $drc_rpt "NSTD"]
set has_ucio [report_has $drc_rpt "UCIO"]

set run_bit [file join [get_property DIRECTORY [get_runs impl_1]] "top.bit"]
set bitgen_success 0
set bit_sha ""
if {[file exists $run_bit]} {
    file copy -force $run_bit $final_bit
    file copy -force $run_bit $root_bit
    set bit_sha [sha256_file $final_bit]
    set bitgen_success 1
}

set fp [open $summary_txt w]
puts $fp "BUILD_TAG=$build_tag"
puts $fp "TOP=$top_module"
puts $fp "ENABLED_XDCS=$enabled_xdcs"
puts $fp "VERILOG_DEFINE=[get_property verilog_define $fs]"
puts $fp "TARGET_FREQ_MHZ=$target_freq_mhz"
puts $fp "ACTIVE_IROM=$active_irom"
puts $fp "ACTIVE_IROM_SHA256=$irom_sha"
puts $fp "ACTIVE_DRAM=$active_dram"
puts $fp "ACTIVE_DRAM_SHA256=$dram_sha"
puts $fp "MYCPU_SHA256=[sha256_file $mycpu_sv]"
puts $fp "Z_DECODE_SHA256=[sha256_file $z_decode_sv]"
puts $fp "Z_UNIT_SHA256=[sha256_file $z_unit_sv]"
puts $fp "PERIP_BRIDGE_SHA256=[sha256_file $perip_bridge_sv]"
puts $fp "STUDENT_TOP_SHA256=[sha256_file $student_top_sv]"
puts $fp "PLL_XCI_SHA256=[sha256_file $pll_xci]"
puts $fp "IROM_BRAM_XCI_SHA256=[sha256_file $irom_bram_xci]"
puts $fp "SOURCE_COMPILE_ORDER=$compile_order_rpt"
puts $fp "RESUME_EXISTING_ROUTE=0"
puts $fp "OPEN_CHECKPOINT_USED=0"
puts $fp "RERAN_SYNTHESIS=1"
puts $fp "RERAN_IMPLEMENTATION=1"
puts $fp "IROM_IP_REFRESHED=1"
puts $fp "IROM_BRAM_IP_REFRESHED=1"
puts $fp "DRAM_IP_REFRESHED=1"
puts $fp "PLL_IP_REFRESHED=1"
puts $fp "WNS=$wns"
puts $fp "TNS=$tns"
puts $fp "WHS=$whs"
puts $fp "DRC_ERROR_COUNT=$drc_error_count"
puts $fp "HAS_BIVC=$has_bivc"
puts $fp "HAS_NSTD=$has_nstd"
puts $fp "HAS_UCIO=$has_ucio"
puts $fp "BITGEN_SUCCESS=$bitgen_success"
puts $fp "ROOT_BIT=$root_bit"
puts $fp "FINAL_BIT=$final_bit"
puts $fp "BIT_SHA256=$bit_sha"
puts $fp "TIMING_REPORT=$timing_rpt"
puts $fp "TOP3_TIMING_REPORT=$timing_paths_rpt"
puts $fp "DRC_REPORT=$drc_rpt"
close $fp

puts "WNS=$wns"
puts "TNS=$tns"
puts "WHS=$whs"
puts "DRC_ERROR_COUNT=$drc_error_count"
puts "BITGEN_SUCCESS=$bitgen_success"
puts "FINAL_BIT=$final_bit"
puts "BIT_SHA256=$bit_sha"
puts "SUMMARY_TXT=$summary_txt"

close_project
if {!$bitgen_success || $drc_error_count != 0} { exit 2 }
exit 0
