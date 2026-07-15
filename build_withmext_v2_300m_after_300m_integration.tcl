set project_root [file normalize [pwd]]
set xpr [file join $project_root "digital_twin.xpr"]
if {[llength [info commands _orig_puts]] == 0} {
    rename puts _orig_puts
    proc puts {args} {
        catch {uplevel 1 [linsert $args 0 _orig_puts]}
    }
}
set sweep_freq_mhz 300.000
set sweep_mode "BASE"
if {[llength $argv] >= 1} {
    set sweep_freq_mhz [lindex $argv 0]
}
if {[llength $argv] >= 2} {
    set sweep_mode [string toupper [lindex $argv 1]]
}
if {$sweep_mode ne "BASE" && $sweep_mode ne "OPT"} {
    error "Unknown sweep mode '$sweep_mode'; expected BASE or OPT"
}
set freq_label [format "%.0f" $sweep_freq_mhz]
set mode_suffix ""
set mode_suffix_lower ""
if {$sweep_mode eq "OPT"} {
    set mode_suffix "_OPT"
    set mode_suffix_lower "_opt"
}

set out_dir [file join $project_root "withmext_${freq_label}m_timing_sweep${mode_suffix_lower}_build_outputs"]
set final_dir [file join $project_root "final_bits"]
set stamp [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set build_tag "WITHMEXT_V2_${freq_label}MHz_TIMING_SWEEP${mode_suffix}_${stamp}"

set root_bit [file join $project_root "WITHMEXT_V2_${freq_label}MHz_TIMING_SWEEP${mode_suffix}.bit"]
set final_bit [file join $final_dir "${build_tag}.bit"]
set summary_md [file join $project_root "WITHMEXT_V2_${freq_label}M_TIMING_SWEEP${mode_suffix}_REPORT.md"]
set summary_txt [file join $out_dir "summary_${build_tag}.txt"]
set timing_rpt [file join $out_dir "timing_${build_tag}.rpt"]
set timing_paths_rpt [file join $out_dir "timing_paths_top3_${build_tag}.rpt"]
set drc_rpt [file join $out_dir "drc_${build_tag}.rpt"]
set compile_order_rpt [file join $out_dir "compile_order_${build_tag}.txt"]
set exceptions_rpt [file join $out_dir "exceptions_${build_tag}.rpt"]

set jobs 8
set top_module "top"
set target_freq_mhz $sweep_freq_mhz
set expected_irom_sha "0CEA80F2CA36E2672AC8D1E3D0087F88DC24B5A33A177C74B47330B0637C6A1B"
set expected_dram_sha "D1C6D8F4ADBE80D618CCFCCC0336A9A61B56007B0F44A4E79BDDF71CCAB89C03"

set source_irom [file join $project_root "digital_twin.srcs" "file_coe" "coe" "withMext" "demo" "irom-v2.coe"]
set source_dram [file join $project_root "digital_twin.srcs" "file_coe" "coe" "withMext" "demo" "dram.coe"]
set active_irom [file join $project_root "digital_twin.srcs" "sources_1" "imports" "test_src" "irom.coe"]
set active_dram [file join $project_root "digital_twin.srcs" "sources_1" "imports" "test_src" "dram.coe"]
set dram_driver [file join $project_root "digital_twin.srcs" "sources_1" "new" "dram_driver.sv"]
set main_xdc [file join $project_root "digital_twin.srcs" "constrs_1" "new" "digital_twin.xdc"]
set virtual_cdc_xdc [file join $project_root "digital_twin.srcs" "constrs_1" "new" "mainline_virtual_platform_cdc.xdc"]
set top_sv [file join $project_root "digital_twin.srcs" "sources_1" "new" "top.sv"]
set student_top_sv [file join $project_root "digital_twin.srcs" "sources_1" "new" "student_top.sv"]
set mycpu_sv [file join $project_root "digital_twin.srcs" "sources_1" "new" "myCPU.sv"]
set old_mycpu_sv [file join $project_root "digital_twin.srcs" "sources_1" "imports" "new" "myCPU.sv"]
set perip_bridge_sv [file join $project_root "digital_twin.srcs" "sources_1" "new" "perip_bridge.sv"]
set z_decode_sv [file join $project_root "digital_twin.srcs" "sources_1" "new" "z_light_decode.sv"]
set z_unit_sv [file join $project_root "digital_twin.srcs" "sources_1" "imports" "new" "z_light_unit.sv"]
set divider_sv [file join $project_root "digital_twin.srcs" "sources_1" "imports" "new" "Divider.sv"]
set pll_xci [file join $project_root "digital_twin.srcs" "sources_1" "ip" "pll_1" "pll.xci"]
set irom_bram_xci [file join $project_root "digital_twin.srcs" "sources_1" "ip" "IROM_BRAM" "IROM_BRAM.xci"]
set irom_bram_mif_gen [file join $project_root "digital_twin.gen" "sources_1" "ip" "IROM_BRAM" "IROM_BRAM.mif"]
set irom_bram_mif_src [file join $project_root "digital_twin.srcs" "sources_1" "ip" "IROM_BRAM" "IROM_BRAM.mif"]

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

proc parse_worst_path_info {rpt} {
    set source ""
    set dest ""
    set logic_delay ""
    set route_delay ""
    if {![file exists $rpt]} { return [list $source $dest $logic_delay $route_delay] }
    set fp [open $rpt r]
    set text [read $fp]
    close $fp
    foreach line [split $text "\n"] {
        if {$source eq "" && [regexp {^\s*Source:\s+(.+)$} $line -> val]} { set source [string trim $val] }
        if {$dest eq "" && [regexp {^\s*Destination:\s+(.+)$} $line -> val]} { set dest [string trim $val] }
        if {$logic_delay eq "" && [regexp {^\s*Data Path Delay:\s+[0-9.]+ns\s+\(logic\s+([0-9.]+)ns\s+\([0-9.]+%\)\s+route\s+([0-9.]+)ns\s+\([0-9.]+%\)\)} $line -> l r]} {
            set logic_delay $l
            set route_delay $r
        }
        if {$source ne "" && $dest ne "" && $logic_delay ne ""} { break }
    }
    return [list $source $dest $logic_delay $route_delay]
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
puts "ENABLE_Z_B_SMALL=0"
puts "MAINLINE_VIRTUAL_PLATFORM_CDC_CUT=1"
puts "SWEEP_MODE=$sweep_mode"

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

set cpu_changed_files ""
catch {
    set cpu_changed_files [exec git diff --name-only HEAD -- \
        digital_twin.srcs/sources_1/new/myCPU.sv \
        digital_twin.srcs/sources_1/imports/new/Divider.sv \
        digital_twin.srcs/sources_1/imports/new/z_light_unit.sv \
        digital_twin.srcs/sources_1/new/z_light_decode.sv]
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
    error "Missing IROM_BRAM IP $irom_bram_xci"
}
if {[llength [get_files -quiet [file normalize $irom_bram_xci]]] == 0} {
    add_files -fileset sources_1 $irom_bram_xci
}

set constrs [get_filesets constrs_1]
set enabled_xdcs {}
if {[llength [get_files -quiet [file normalize $virtual_cdc_xdc]]] == 0} {
    add_files -fileset constrs_1 $virtual_cdc_xdc
}
foreach cf [get_files -of_objects $constrs] {
    if {[string tolower [file extension $cf]] eq ".xdc"} {
        set cf_norm [file normalize $cf]
        set used [expr {$cf_norm eq [file normalize $main_xdc] || $cf_norm eq [file normalize $virtual_cdc_xdc]}]
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
catch {set_property AUTO_INCREMENTAL_CHECKPOINT 0 $synth_run}
catch {set_property INCREMENTAL_CHECKPOINT {} $synth_run}
catch {set_property STEPS.SYNTH_DESIGN.ARGS.INCREMENTAL_MODE off $synth_run}
catch {set_property AUTO_INCREMENTAL_CHECKPOINT 0 $impl_run}
catch {set_property INCREMENTAL_CHECKPOINT {} $impl_run}
catch {set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Explore $impl_run}
catch {set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $impl_run}
catch {set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl_run}
if {$sweep_mode eq "OPT"} {
    catch {set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraNetDelay_high $impl_run}
    catch {set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl_run}
} else {
    catch {set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore $impl_run}
    catch {set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore $impl_run}
}
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
report_exceptions -file $exceptions_rpt
report_drc -file $drc_rpt

set timing_vals [parse_timing_summary_values $timing_rpt]
set wns [lindex $timing_vals 0]
set tns [lindex $timing_vals 1]
set whs [lindex $timing_vals 2]
set clk_vals [parse_clkout2_values $timing_rpt]
set cpu_clk_period [lindex $clk_vals 0]
set cpu_clk_freq [lindex $clk_vals 1]
set worst_vals [parse_worst_path_info $timing_paths_rpt]
set worst_source [lindex $worst_vals 0]
set worst_dest [lindex $worst_vals 1]
set worst_logic_delay [lindex $worst_vals 2]
set worst_route_delay [lindex $worst_vals 3]
set drc_error_count [drc_report_error_count $drc_rpt]
set has_bivc [report_has $drc_rpt "BIVC"]
set has_nstd [report_has $drc_rpt "NSTD"]
set has_ucio [report_has $drc_rpt "UCIO"]

set irom_bram_mif_sha ""
if {[file exists $irom_bram_mif_gen]} {
    set irom_bram_mif_sha [sha256_file $irom_bram_mif_gen]
} elseif {[file exists $irom_bram_mif_src]} {
    set irom_bram_mif_sha [sha256_file $irom_bram_mif_src]
}

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
puts $fp "ENABLE_Z_B_SMALL=0"
puts $fp "MAINLINE_VIRTUAL_PLATFORM_CDC_CUT=1"
puts $fp "SWEEP_MODE=$sweep_mode"
puts $fp "IMPLEMENTATION_STRATEGY=Performance_Explore"
puts $fp "OPT_DESIGN_DIRECTIVE=[get_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE $impl_run]"
puts $fp "PLACE_DESIGN_DIRECTIVE=[get_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $impl_run]"
puts $fp "PHYS_OPT_DESIGN_DIRECTIVE=[get_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE $impl_run]"
puts $fp "ROUTE_DESIGN_DIRECTIVE=[get_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE $impl_run]"
puts $fp "POST_ROUTE_PHYS_OPT_DESIGN_DIRECTIVE=[get_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE $impl_run]"
puts $fp "TARGET_FREQ_MHZ=$target_freq_mhz"
puts $fp "CPU_CLOCK_PERIOD_NS=$cpu_clk_period"
puts $fp "CPU_CLOCK_FREQ_MHZ=$cpu_clk_freq"
puts $fp "ACTIVE_IROM_SHA256=$irom_sha"
puts $fp "ACTIVE_DRAM_SHA256=$dram_sha"
puts $fp "DRAM_DRIVER_SYNC_STATUS=$dram_sync"
puts $fp "IROM_BRAM_MIF_SHA256=$irom_bram_mif_sha"
puts $fp "MYCPU_SHA256=[sha256_file $mycpu_sv]"
puts $fp "PERIP_BRIDGE_SHA256=[sha256_file $perip_bridge_sv]"
puts $fp "Z_DECODE_SHA256=[sha256_file $z_decode_sv]"
puts $fp "Z_UNIT_SHA256=[sha256_file $z_unit_sv]"
puts $fp "STUDENT_TOP_SHA256=[sha256_file $student_top_sv]"
puts $fp "PLL_XCI_SHA256=[sha256_file $pll_xci]"
puts $fp "IROM_BRAM_XCI_SHA256=[sha256_file $irom_bram_xci]"
puts $fp "CPU_CHANGED_FILES=$cpu_changed_files"
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
puts $fp "WORST_SOURCE=$worst_source"
puts $fp "WORST_DESTINATION=$worst_dest"
puts $fp "WORST_LOGIC_DELAY_NS=$worst_logic_delay"
puts $fp "WORST_ROUTE_DELAY_NS=$worst_route_delay"
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
puts $fp "EXCEPTIONS_REPORT=$exceptions_rpt"
close $fp

set md [open $summary_md w]
puts $md "# WITHMEXT_V2_${freq_label}M_TIMING_SWEEP${mode_suffix}_REPORT"
puts $md ""
puts $md "- Bit: `$final_bit`"
puts $md "- Root bit: `$root_bit`"
puts $md "- Bit SHA256: `$bit_sha`"
puts $md "- IROM SHA256: `$irom_sha`"
puts $md "- DRAM SHA256: `$dram_sha`"
puts $md "- IROM_BRAM.mif SHA256: `$irom_bram_mif_sha`"
puts $md "- CPU clock target: `${target_freq_mhz} MHz`"
puts $md "- CPU clock report: `${cpu_clk_freq} MHz`, period `${cpu_clk_period} ns`"
puts $md "- WNS/TNS/WHS: `$wns / $tns / $whs`"
puts $md "- DRC errors: `$drc_error_count`"
puts $md "- BIVC/NSTD/UCIO: `$has_bivc / $has_nstd / $has_ucio`"
puts $md "- Worst source: `$worst_source`"
puts $md "- Worst destination: `$worst_dest`"
puts $md "- Worst path logic/route delay: `$worst_logic_delay ns / $worst_route_delay ns`"
puts $md "- ENABLE_Z_B_SMALL: off, `verilog_define` = `[get_property verilog_define $fs]`"
puts $md "- Mainline virtual-platform CDC cut: enabled via `mainline_virtual_platform_cdc.xdc`."
puts $md "- Sweep mode: `$sweep_mode`"
puts $md "- Implementation strategy: `Performance_Explore`"
puts $md "- Directives: opt `[get_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE $impl_run]`, place `[get_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $impl_run]`, phys_opt `[get_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE $impl_run]`, route `[get_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE $impl_run]`, post-route phys_opt `[get_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE $impl_run]`"
puts $md "- Synchronous IROM_BRAM preserved: `student_top.sv` instantiates `IROM_BRAM(.clka, .ena, .addra, .douta)`."
puts $md "- CPU changed files relative to HEAD: `$cpu_changed_files`"
puts $md "- top: `$top_module`"
puts $md "- XDC list: `$enabled_xdcs`"
puts $md "- compile order: `$compile_order_rpt`"
puts $md "- Resume/open_checkpoint: `0 / 0`"
puts $md "- IROM/IP refresh: `IROM=1`, `IROM_BRAM=1`, `DRAM=1`, `PLL=1`"
puts $md "- Board expectation: left check, 8 official lights on, `SEG=378xxxxx`."
puts $md "- Board result: pending."
puts $md "- Summary txt: `$summary_txt`"
puts $md "- Timing report: `$timing_rpt`"
puts $md "- Top 3 timing report: `$timing_paths_rpt`"
puts $md "- DRC report: `$drc_rpt`"
puts $md "- Exceptions report: `$exceptions_rpt`"
close $md

puts "BUILD_TAG=$build_tag"
puts "CPU_CLOCK_PERIOD_NS=$cpu_clk_period"
puts "CPU_CLOCK_FREQ_MHZ=$cpu_clk_freq"
puts "ACTIVE_IROM_SHA256=$irom_sha"
puts "ACTIVE_DRAM_SHA256=$dram_sha"
puts "IROM_BRAM_MIF_SHA256=$irom_bram_mif_sha"
puts "ENABLE_Z_B_SMALL=0"
puts "MAINLINE_VIRTUAL_PLATFORM_CDC_CUT=1"
puts "SWEEP_MODE=$sweep_mode"
puts "WNS=$wns"
puts "TNS=$tns"
puts "WHS=$whs"
puts "DRC_ERROR_COUNT=$drc_error_count"
puts "WORST_SOURCE=$worst_source"
puts "WORST_DESTINATION=$worst_dest"
puts "BITGEN_SUCCESS=$bitgen_success"
puts "FINAL_BIT=$final_bit"
puts "BIT_SHA256=$bit_sha"
puts "SUMMARY_MD=$summary_md"

close_project
if {!$bitgen_success || $drc_error_count != 0} { exit 2 }
exit 0

