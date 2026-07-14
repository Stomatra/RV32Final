set project_root [file normalize [pwd]]
set xpr [file join $project_root "digital_twin.xpr"]
set out_dir [file join $project_root "ip_restore_build_outputs"]
set final_dir [file join $project_root "final_bits"]
set stamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set build_tag "IP_RESTORED_withMext_v2_200MHz_${stamp}"

set root_bit [file join $project_root "IP_RESTORED_withMext_v2_200MHz.bit"]
set final_bit [file join $final_dir "${build_tag}.bit"]
set summary_md [file join $project_root "IP_RESTORE_200M_REPORT.md"]
set summary_txt [file join $out_dir "summary_${build_tag}.txt"]
set timing_rpt [file join $out_dir "timing_${build_tag}.rpt"]
set timing_paths_rpt [file join $out_dir "timing_paths_top3_${build_tag}.rpt"]
set clocks_rpt [file join $out_dir "clocks_${build_tag}.rpt"]
set drc_rpt [file join $out_dir "drc_${build_tag}.rpt"]
set compile_order_rpt [file join $out_dir "compile_order_${build_tag}.txt"]

set jobs 8
set top_module "top"
set target_freq_mhz 200.000
set target_period_ns 5.000
set expected_irom_sha "0CEA80F2CA36E2672AC8D1E3D0087F88DC24B5A33A177C74B47330B0637C6A1B"
set expected_dram_sha "D1C6D8F4ADBE80D618CCFCCC0336A9A61B56007B0F44A4E79BDDF71CCAB89C03"

set source_irom [file join $project_root "digital_twin.srcs" "file_coe" "coe" "withMext" "demo" "irom-v2.coe"]
set source_dram [file join $project_root "digital_twin.srcs" "file_coe" "coe" "withMext" "demo" "dram.coe"]
set active_irom [file join $project_root "digital_twin.srcs" "sources_1" "imports" "test_src" "irom.coe"]
set active_dram [file join $project_root "digital_twin.srcs" "sources_1" "imports" "test_src" "dram.coe"]
set dram_driver [file join $project_root "digital_twin.srcs" "sources_1" "new" "dram_driver.sv"]
set main_xdc [file join $project_root "digital_twin.srcs" "constrs_1" "new" "digital_twin.xdc"]
set top_sv [file join $project_root "digital_twin.srcs" "sources_1" "new" "top.sv"]
set student_top_sv [file join $project_root "digital_twin.srcs" "sources_1" "new" "student_top.sv"]
set mycpu_sv [file join $project_root "digital_twin.srcs" "sources_1" "new" "myCPU.sv"]
set old_mycpu_sv [file join $project_root "digital_twin.srcs" "sources_1" "imports" "new" "myCPU.sv"]
set perip_bridge_sv [file join $project_root "digital_twin.srcs" "sources_1" "new" "perip_bridge.sv"]
set pll_xci [file join $project_root "digital_twin.srcs" "sources_1" "ip" "pll_1" "pll.xci"]
set irom_bram_xci [file join $project_root "digital_twin.srcs" "sources_1" "ip" "IROM_BRAM" "IROM_BRAM.xci"]
set irom_bram_mif [file join $project_root "digital_twin.gen" "sources_1" "ip" "IROM_BRAM" "IROM_BRAM.mif"]
set irom_bram_1_xci [file join $project_root "digital_twin.srcs" "sources_1" "ip" "IROM_BRAM_1" "IROM_BRAM.xci"]
set migrated_manifest [file join $project_root "SHELL_CLEAN_MIGRATED_FILES.tsv"]
set shell_snapshot_manifest [file join $project_root "shell_original_snapshot_before_migration" "sha256_manifest.tsv"]

file mkdir $out_dir
file mkdir $final_dir

proc sha256_file {path} {
    set normalized [file normalize $path]
    set output [exec certutil -hashfile $normalized SHA256]
    foreach line [split $output "\n"] {
        set trimmed [string trim $line]
        if {[regexp {^[0-9A-Fa-f]{64}$} $trimmed]} {
            return [string toupper $trimmed]
        }
    }
    error "Cannot parse SHA256 for $normalized"
}

proc coe_words {path} {
    set fp [open $path r]
    set text [read $fp]
    close $fp
    regsub -all {\r} $text "" text
    set words {}
    set in_vec 0
    foreach raw [split $text "\n"] {
        set line [string trim $raw]
        if {$line eq ""} { continue }
        if {[string first "memory_initialization_vector" $line] >= 0} {
            set in_vec 1
            set line [lindex [split $line "="] end]
        }
        if {!$in_vec} { continue }
        foreach item [split $line ","] {
            set w [string trim [string trim $item ";"]]
            if {$w eq ""} { continue }
            if {[regexp {^[0-9A-Fa-f]+$} $w]} {
                lappend words [format "%08X" [expr 0x$w]]
            }
        }
    }
    return $words
}

proc dram_driver_sync_status {coe driver} {
    set words [coe_words $coe]
    set fp [open $driver r]
    set text [read $fp]
    close $fp
    array set lanes {}
    foreach {all lane idx byte} [regexp -all -inline {dram_lane([0-3])\s*\[\s*16'd([0-9]+)\s*\]\s*=\s*8'h([0-9A-Fa-f]{2})} $text] {
        set lanes($idx,$lane) [string toupper $byte]
    }
    set mismatches 0
    set checked 0
    for {set i 0} {$i < [llength $words]} {incr i} {
        set w [lindex $words $i]
        set exp0 [string range $w 6 7]
        set exp1 [string range $w 4 5]
        set exp2 [string range $w 2 3]
        set exp3 [string range $w 0 1]
        foreach lane {0 1 2 3} exp [list $exp0 $exp1 $exp2 $exp3] {
            if {![info exists lanes($i,$lane)] || $lanes($i,$lane) ne $exp} {
                incr mismatches
            }
        }
        incr checked
    }
    return [format "%d words=%d mismatches=%d" [expr {$mismatches == 0}] $checked $mismatches]
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

proc parse_clkout2_values {rpt} {
    if {![file exists $rpt]} { return [list "" ""] }
    set fp [open $rpt r]
    set text [read $fp]
    close $fp
    foreach line [split $text "\n"] {
        if {[regexp {^\s*clk_out2_pll\s+\{[^\}]+\}\s+([0-9]+\.[0-9]+)\s+([0-9]+\.[0-9]+)\s*} $line -> period freq]} {
            return [list $period $freq]
        }
    }
    return [list "" ""]
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

puts "SHELL_CLEAN_BUILD=1"
puts "RESUME_EXISTING_ROUTE=0"
puts "OPEN_CHECKPOINT_USED=0"

copy_checked $source_irom $active_irom
copy_checked $source_dram $active_dram

set irom_sha [sha256_file $active_irom]
set dram_sha [sha256_file $active_dram]
if {$irom_sha ne $expected_irom_sha} { error "IROM SHA mismatch: $irom_sha" }
if {$dram_sha ne $expected_dram_sha} { error "DRAM SHA mismatch: $dram_sha" }

set dram_sync [dram_driver_sync_status $active_dram $dram_driver]
if {![string match "1 *" $dram_sync]} {
    error "dram_driver.sv is not synchronized: $dram_sync"
}

open_project $xpr

set fs [get_filesets sources_1]
set_property top $top_module $fs
set_property verilog_define {} $fs
set_property generic {} $fs

set old_file [get_files -quiet [file normalize $old_mycpu_sv]]
if {[llength $old_file] > 0} {
    remove_files $old_file
}

set needed_files [list \
    $mycpu_sv \
    [file join $project_root "digital_twin.srcs" "sources_1" "new" "z_light_decode.sv"] \
    [file join $project_root "digital_twin.srcs" "sources_1" "imports" "new" "z_light_unit.sv"] \
    [file join $project_root "digital_twin.srcs" "sources_1" "imports" "new" "Divider.sv"] \
]
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
if {[llength $irom_bram_ip] == 0} { error "Cannot find restored IROM_BRAM IP" }

foreach ip [list $irom_ip $dram_ip $pll_ip $irom_bram_ip] {
    set locked 0
    catch {set locked [get_property IS_LOCKED $ip]}
    if {$locked} {
        puts "UPGRADE_IP=$ip"
        upgrade_ip $ip
    }
}
set irom_ip [get_ips -quiet IROM]
set dram_ip [get_ips -quiet DRAM]
set pll_ip [get_ips -quiet pll]
set irom_bram_ip [get_ips -quiet IROM_BRAM]

puts "CONFIGURE_PLL_CLKOUT2_MHZ=$target_freq_mhz"
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
set clk_vals [parse_clkout2_values $timing_rpt]
set cpu_clk_period [lindex $clk_vals 0]
set cpu_clk_freq [lindex $clk_vals 1]
set clk_fp [open $clocks_rpt w]
puts $clk_fp "clk_out2_pll period_ns=$cpu_clk_period frequency_mhz=$cpu_clk_freq"
close $clk_fp

set drc_error_count [drc_report_error_count $drc_rpt]
set has_bivc [report_has $drc_rpt "BIVC"]
set has_nstd [report_has $drc_rpt "NSTD"]
set has_ucio [report_has $drc_rpt "UCIO"]

set mycpu_sha [sha256_file $mycpu_sv]
set perip_sha [sha256_file $perip_bridge_sv]
set dram_driver_sha [sha256_file $dram_driver]
set pll_sha [sha256_file $pll_xci]
set irom_bram_xci_sha [sha256_file $irom_bram_xci]
set irom_bram_mif_sha ""
if {[file exists $irom_bram_mif]} {
    set irom_bram_mif_sha [sha256_file $irom_bram_mif]
}
set irom_bram_1_xci_sha ""
if {[file exists $irom_bram_1_xci]} {
    set irom_bram_1_xci_sha [sha256_file $irom_bram_1_xci]
}
set current_ips [lsort [get_ips -quiet *]]
set irom_bram_recognized [expr {[llength [get_ips -quiet IROM_BRAM]] > 0}]
set irom_bram_1_recognized [expr {[llength [get_ips -quiet IROM_BRAM_1]] > 0}]
set xdc_sha [sha256_file $main_xdc]
set top_sha [sha256_file $top_sv]
set student_top_sha [sha256_file $student_top_sv]

set run_bit [file join [get_property DIRECTORY [get_runs impl_1]] "top.bit"]
set bitgen_success 0
set bit_sha ""
if {$drc_error_count == 0 && $wns ne "" && $whs ne "" && $wns >= 0 && $whs >= 0 && [file exists $run_bit]} {
    file copy -force $run_bit $final_bit
    file copy -force $run_bit $root_bit
    set bit_sha [sha256_file $final_bit]
    set bitgen_success 1
}

set fp [open $summary_txt w]
puts $fp "BUILD_TAG=$build_tag"
puts $fp "TOP=$top_module"
puts $fp "ENABLED_XDCS=$enabled_xdcs"
puts $fp "TARGET_FREQ_MHZ=$target_freq_mhz"
puts $fp "TARGET_PERIOD_NS=$target_period_ns"
puts $fp "CPU_CLOCK_PERIOD_NS=$cpu_clk_period"
puts $fp "CPU_CLOCK_FREQ_MHZ=$cpu_clk_freq"
puts $fp "ACTIVE_IROM_SHA256=$irom_sha"
puts $fp "ACTIVE_DRAM_SHA256=$dram_sha"
puts $fp "DRAM_DRIVER_SYNC_STATUS=$dram_sync"
puts $fp "MYCPU_SHA256=$mycpu_sha"
puts $fp "PERIP_BRIDGE_SHA256=$perip_sha"
puts $fp "DRAM_DRIVER_SHA256=$dram_driver_sha"
puts $fp "PLL_XCI_SHA256=$pll_sha"
puts $fp "IROM_BRAM_XCI_SHA256=$irom_bram_xci_sha"
puts $fp "IROM_BRAM_MIF_SHA256=$irom_bram_mif_sha"
puts $fp "IROM_BRAM_1_XCI_SHA256=$irom_bram_1_xci_sha"
puts $fp "GET_IPS=$current_ips"
puts $fp "IROM_BRAM_RECOGNIZED=$irom_bram_recognized"
puts $fp "IROM_BRAM_1_RECOGNIZED=$irom_bram_1_recognized"
puts $fp "DIGITAL_TWIN_XDC_SHA256=$xdc_sha"
puts $fp "TOP_SV_SHA256=$top_sha"
puts $fp "STUDENT_TOP_SHA256=$student_top_sha"
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
puts $fp "FINAL_BIT=$final_bit"
puts $fp "BIT_SHA256=$bit_sha"
puts $fp "TIMING_REPORT=$timing_rpt"
puts $fp "TOP3_TIMING_REPORT=$timing_paths_rpt"
puts $fp "DRC_REPORT=$drc_rpt"
close $fp

set md [open $summary_md w]
puts $md "# IP_RESTORE_200M_REPORT"
puts $md ""
puts $md "- Shell source: official clean shell extracted into `$project_root` before migration."
puts $md "- Borrowed IP audit: `BORROWED_IP_AUDIT.md`"
puts $md "- Current IP audit before restore: `CURRENT_IP_AUDIT.md`"
puts $md "- Restored IP folders: `IROM_BRAM`, `IROM_BRAM_1` copied into `digital_twin.srcs/sources_1/ip` and `digital_twin.gen/sources_1/ip`."
puts $md "- Note: `IROM_BRAM_1/IROM_BRAM.xci` has the same IP component name as `IROM_BRAM`, so only `IROM_BRAM/IROM_BRAM.xci` was added as a Vivado IP to avoid duplicate IP instance names."
puts $md "- `student_top.sv` now instantiates synchronous `IROM_BRAM` instead of asynchronous `IROM`, matching the current `myCPU.sv` fetch pipeline comments/logic."
puts $md "- Not migrated from old project: HDMI tops, UART echo/debug tops, `uart_rx.sv`, HDMI serializer/colorbar files, cpu_hdmi XDC files, smoke/echo/debug IROMs, old runs/cache/.Xil/checkpoints/build_outputs."
puts $md "- top: `$top_module`"
puts $md "- XDC list: `$enabled_xdcs`"
puts $md "- compile order: `$compile_order_rpt`"
puts $md "- get_ips: `$current_ips`"
puts $md "- IROM_BRAM recognized by Vivado: `$irom_bram_recognized`"
puts $md "- IROM_BRAM_1 recognized by Vivado: `$irom_bram_1_recognized`"
puts $md "- IROM SHA256: `$irom_sha`"
puts $md "- DRAM SHA256: `$dram_sha`"
puts $md "- IROM_BRAM.xci SHA256: `$irom_bram_xci_sha`"
puts $md "- IROM_BRAM.mif SHA256: `$irom_bram_mif_sha`"
puts $md "- IROM_BRAM_1/IROM_BRAM.xci SHA256: `$irom_bram_1_xci_sha`"
puts $md "- dram_driver sync: `$dram_sync`"
puts $md "- dram_driver.sv SHA256: `$dram_driver_sha`"
puts $md "- myCPU.sv SHA256: `$mycpu_sha`"
puts $md "- perip_bridge.sv SHA256: `$perip_sha`"
puts $md "- pll.xci SHA256: `$pll_sha`"
puts $md "- digital_twin.xdc SHA256: `$xdc_sha`"
puts $md "- report_clocks clk_out2_pll period/freq: `${cpu_clk_period} ns / ${cpu_clk_freq} MHz`"
puts $md "- WNS/TNS/WHS: `$wns / $tns / $whs`"
puts $md "- DRC errors: `$drc_error_count`"
puts $md "- BIVC/NSTD/UCIO: `$has_bivc / $has_nstd / $has_ucio`"
puts $md "- bit path: `$final_bit`"
puts $md "- root bit path: `$root_bit`"
puts $md "- bit SHA256: `$bit_sha`"
puts $md "- timing report: `$timing_rpt`"
puts $md "- DRC report: `$drc_rpt`"
close $md

puts "BUILD_TAG=$build_tag"
puts "TOP=$top_module"
puts "CPU_CLOCK_PERIOD_NS=$cpu_clk_period"
puts "CPU_CLOCK_FREQ_MHZ=$cpu_clk_freq"
puts "ACTIVE_IROM_SHA256=$irom_sha"
puts "ACTIVE_DRAM_SHA256=$dram_sha"
puts "DRAM_DRIVER_SYNC_STATUS=$dram_sync"
puts "GET_IPS=$current_ips"
puts "IROM_BRAM_RECOGNIZED=$irom_bram_recognized"
puts "WNS=$wns"
puts "TNS=$tns"
puts "WHS=$whs"
puts "DRC_ERROR_COUNT=$drc_error_count"
puts "BITGEN_SUCCESS=$bitgen_success"
puts "FINAL_BIT=$final_bit"
puts "BIT_SHA256=$bit_sha"
puts "SUMMARY_MD=$summary_md"

close_project
if {!$bitgen_success} { exit 2 }
exit 0
