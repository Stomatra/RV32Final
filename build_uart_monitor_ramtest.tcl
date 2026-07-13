set mode "plain"
if {[info exists argv] && [llength $argv] > 0} {
    set mode [lindex $argv 0]
}
if {![regexp {^(plain|hdmi)$} $mode]} {
    error "Unsupported mode '$mode'. Use plain or hdmi."
}

set is_hdmi [expr {$mode eq "hdmi"}]
set project_dir "build_outputs/uart_monitor_ramtest_${mode}_project"
set project_name "uart_monitor_ramtest_${mode}"
set timestamp [clock format [clock seconds] -format {%Y%m%d_%H%M%S}]
if {$is_hdmi} {
    set top_module "top_cpu_hdmi_uart_rx_echo_status"
    set bit_file "cpu_hdmi_uart_monitor_ramtest_status.bit"
    set build_tag "CPU_HDMI_UART_MONITOR_RAMTEST_STATUS_720p60_200m_${timestamp}"
} else {
    set top_module "top_uart_rx_echo_test"
    set bit_file "uart_monitor_ramtest.bit"
    set build_tag "UART_MONITOR_RAMTEST_200m_${timestamp}"
}

set source_irom "digital_twin.srcs/sources_1/imports/test_src/irom-uart-monitor-ramtest.coe"
set active_irom "digital_twin.srcs/sources_1/imports/test_src/irom.coe"
set irom_xci "digital_twin.srcs/sources_1/ip/IROM/IROM.xci"
set generated_irom_sv "build_outputs/generated_irom_uart_monitor_ramtest.sv"
set dram_addr_start "0x80100000"
set dram_addr_end "0x8013FFFF"
set ram_test_words 256
set dump_words 16

proc sha256_file {path} {
    set normalized [file normalize $path]
    set output [exec certutil -hashfile $normalized SHA256]
    foreach line [split $output "\n"] {
        set trimmed [string trim $line]
        if {[regexp {^[0-9A-Fa-f]{64}$} $trimmed]} {
            return [string toupper $trimmed]
        }
    }
    error "Cannot parse SHA256 from certutil output for $normalized"
}

proc parse_coe_words {coe_path} {
    set in [open $coe_path r]
    set text [read $in]
    close $in

    regsub -all {\r} $text "" text
    set lower [string tolower $text]
    set marker "memory_initialization_vector"
    set marker_pos [string first $marker $lower]
    if {$marker_pos < 0} {
        error "Cannot find memory_initialization_vector in $coe_path"
    }
    set eq_pos [string first "=" $text $marker_pos]
    if {$eq_pos < 0} {
        error "Cannot find '=' after memory_initialization_vector in $coe_path"
    }
    set vector_text [string range $text [expr {$eq_pos + 1}] end]
    regsub -all {[;\n\t\r ]+} $vector_text "," vector_text
    set raw_tokens [split $vector_text ","]

    set words {}
    foreach token $raw_tokens {
        set trimmed [string trim $token]
        if {$trimmed eq ""} {
            continue
        }
        if {![regexp {^[0-9A-Fa-f]+$} $trimmed]} {
            continue
        }
        set upper [string toupper $trimmed]
        if {[string length $upper] > 8} {
            set upper [string range $upper end-7 end]
        }
        while {[string length $upper] < 8} {
            set upper "0$upper"
        }
        lappend words $upper
    }
    if {[llength $words] == 0} {
        error "No ROM words parsed from $coe_path"
    }
    return $words
}

proc first_words_string {words count} {
    set out {}
    for {set i 0} {$i < $count} {incr i} {
        if {$i < [llength $words]} {
            lappend out [lindex $words $i]
        } else {
            lappend out "00000000"
        }
    }
    return [join $out ","]
}

proc write_irom_sv_from_words {words sv_path} {
    if {[llength $words] > 4096} {
        error "IROM COE has [llength $words] words, exceeds 4096"
    }
    file mkdir [file dirname $sv_path]
    set out [open $sv_path w]
    puts $out {`timescale 1ns / 1ps}
    puts $out {}
    puts $out {module IROM (}
    puts $out {    input  logic [11:0] a,}
    puts $out {    output logic [31:0] spo}
    puts $out {);}
    puts $out {    (* rom_style = "distributed" *) logic [31:0] rom [0:4095];}
    puts $out {    integer i;}
    puts $out {}
    puts $out {    initial begin}
    puts $out {        for (i = 0; i < 4096; i = i + 1) begin}
    puts $out {            rom[i] = 32'h00000000;}
    puts $out {        end}
    for {set idx 0} {$idx < [llength $words]} {incr idx} {
        puts $out [format "        rom\[%d\] = 32'h%s;" $idx [lindex $words $idx]]
    }
    puts $out {    end}
    puts $out {}
    puts $out {    always_comb begin}
    puts $out {        spo = rom[a];}
    puts $out {    end}
    puts $out {}
    puts $out {endmodule}
    close $out
}

proc refresh_irom_ip_outputs {irom_xci} {
    if {![file exists $irom_xci]} {
        puts "IROM_IP_REFRESHED=0"
        return 0
    }
    set ip_project_dir "build_outputs/uart_monitor_ramtest_ip_refresh_project"
    create_project uart_monitor_ramtest_ip_refresh $ip_project_dir -part xc7k325tffg900-2 -force
    add_files -norecurse $irom_xci
    generate_target all [get_files $irom_xci]
    export_ip_user_files -of_objects [get_files $irom_xci] -no_script -sync -force -quiet
    close_project
    puts "IROM_IP_REFRESHED=1"
    return 1
}

proc drc_report_error_count {rpt} {
    if {![file exists $rpt]} {
        return -1
    }
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

if {![file exists $source_irom]} {
    error "Cannot find UART monitor RAM-test IROM: $source_irom. Run python scripts/gen_irom_uart_monitor_ramtest.py first."
}

file mkdir build_outputs
file mkdir final_bits

file copy -force $source_irom $active_irom
set irom_sha [sha256_file $active_irom]
set source_irom_sha [sha256_file $source_irom]
set irom_words [parse_coe_words $active_irom]
set irom_first8 [first_words_string $irom_words 8]
write_irom_sv_from_words $irom_words $generated_irom_sv
set irom_word_count [llength $irom_words]

puts "UART_MONITOR_RAMTEST_MODE=$mode"
puts "ACTIVE_IROM_PATH=[file normalize $active_irom]"
puts "ACTIVE_IROM_SHA256=$irom_sha"
puts "ACTIVE_IROM_FIRST8=$irom_first8"
puts "SOURCE_IROM_PATH=[file normalize $source_irom]"
puts "SOURCE_IROM_SHA256=$source_irom_sha"
puts "GENERATED_IROM_SV=[file normalize $generated_irom_sv]"
puts "GENERATED_IROM_WORDS=$irom_word_count"
puts "DRAM_ADDR_START=$dram_addr_start"
puts "DRAM_ADDR_END=$dram_addr_end"
puts "RAM_TEST_WORDS=$ram_test_words"

set irom_ip_refreshed [refresh_irom_ip_outputs $irom_xci]

create_project $project_name $project_dir -part xc7k325tffg900-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set common_sv_files [list \
    build_outputs/generated_irom_uart_monitor_ramtest.sv \
    digital_twin.srcs/sources_1/new/cpu_clock_gen_status.sv \
    digital_twin.srcs/sources_1/new/myCPU.sv \
    digital_twin.srcs/sources_1/new/perip_bridge.sv \
    digital_twin.srcs/sources_1/new/counter.sv \
    digital_twin.srcs/sources_1/new/display_seg.sv \
    digital_twin.srcs/sources_1/new/seg7.sv \
    digital_twin.srcs/sources_1/new/dram_driver.sv \
    digital_twin.srcs/sources_1/new/uart_tx.sv \
    digital_twin.srcs/sources_1/new/uart_rx.sv \
    digital_twin.srcs/sources_1/new/z_light_decode.sv \
    digital_twin.srcs/sources_1/imports/new/ACTL.sv \
    digital_twin.srcs/sources_1/imports/new/ALU.sv \
    digital_twin.srcs/sources_1/imports/new/CCTL.sv \
    digital_twin.srcs/sources_1/imports/new/CSR.sv \
    digital_twin.srcs/sources_1/imports/new/Control.sv \
    digital_twin.srcs/sources_1/imports/new/Divider.sv \
    digital_twin.srcs/sources_1/imports/new/IMMGEN.sv \
    digital_twin.srcs/sources_1/imports/new/Mask.sv \
    digital_twin.srcs/sources_1/imports/new/Multiplier.sv \
    digital_twin.srcs/sources_1/imports/new/NPC.sv \
    digital_twin.srcs/sources_1/imports/new/PC.sv \
    digital_twin.srcs/sources_1/imports/new/RF.sv \
    digital_twin.srcs/sources_1/imports/new/defines.sv \
    digital_twin.srcs/sources_1/imports/new/z_light_unit.sv \
]

set xdc_file "digital_twin.srcs/constrs_1/new/uart_rx_echo_only.xdc"
if {$is_hdmi} {
    set mode_sv_files [list \
        digital_twin.srcs/sources_1/new/top_cpu_hdmi_uart_rx_echo_status.sv \
        digital_twin.srcs/sources_1/new/hdmi_clock_gen_720p_ref.sv \
        digital_twin.srcs/sources_1/new/hdmi_uart_status_panel.sv \
        digital_twin.srcs/sources_1/new/hdmi_uart_status_text_overlay.sv \
        digital_twin.srcs/sources_1/new/font_rom_8x16.sv \
        digital_twin.srcs/sources_1/new/hdmi_out_7series_ref.sv \
        digital_twin.srcs/sources_1/new/tmds_encoder.sv \
        digital_twin.srcs/sources_1/new/video_timing_1280x720.sv \
    ]
    set xdc_file "digital_twin.srcs/constrs_1/new/cpu_hdmi_led_seg_status_only.xdc"
} else {
    set mode_sv_files [list \
        digital_twin.srcs/sources_1/new/top_uart_rx_echo_test.sv \
        digital_twin.srcs/sources_1/new/student_top.sv \
    ]
}

set rtl_sv_files [concat $mode_sv_files $common_sv_files]
set rtl_v_files [list \
    digital_twin.srcs/sources_1/imports/new/MuxKey.v \
    digital_twin.srcs/sources_1/imports/new/MuxKeyInternal.v \
]
set memory_files [list \
    digital_twin.srcs/sources_1/imports/test_src/irom.coe \
    digital_twin.srcs/sources_1/imports/test_src/irom-uart-monitor-ramtest.coe \
    digital_twin.srcs/sources_1/imports/test_src/dram.coe \
]

add_files -norecurse -fileset sources_1 $rtl_sv_files
add_files -norecurse -fileset sources_1 $rtl_v_files
add_files -norecurse -fileset sources_1 $memory_files
set_property file_type SystemVerilog [get_files $rtl_sv_files]

add_files -norecurse -fileset constrs_1 $xdc_file
set_property top $top_module [current_fileset]
puts "TOP=$top_module"
puts "XDC=[file normalize $xdc_file]"
puts "VERILOG_DEFINE=[get_property verilog_define [current_fileset]]"

update_compile_order -fileset sources_1

proc dump_drc_and_exit {stage} {
    set rpt "build_outputs/uart_monitor_ramtest_drc_${stage}.rpt"
    catch {report_drc -file $rpt}
    puts "UART_MONITOR_RAMTEST_FAILED_STAGE=$stage"
    puts "UART_MONITOR_RAMTEST_DRC_REPORT=[file normalize $rpt]"
    if {[file exists $rpt]} {
        set fp [open $rpt r]
        puts [read $fp]
        close $fp
    }
    exit 1
}

proc run_or_drc {stage cmd} {
    set code [catch {uplevel 1 $cmd} result]
    if {$code != 0} {
        puts "UART_MONITOR_RAMTEST_ERROR=$result"
        dump_drc_and_exit $stage
    }
}

run_or_drc synth {
    synth_design -top $top_module -part xc7k325tffg900-2
}
report_utilization -file "build_outputs/util_${build_tag}_synth.rpt"

run_or_drc opt {
    opt_design
}
report_drc -file "build_outputs/drc_${build_tag}_opt.rpt"

run_or_drc place {
    place_design
}
report_drc -file "build_outputs/drc_${build_tag}_placed.rpt"

run_or_drc route {
    route_design
}

set timing_rpt "build_outputs/timing_${build_tag}.rpt"
set util_rpt "build_outputs/util_${build_tag}_routed.rpt"
set drc_rpt "build_outputs/drc_${build_tag}_routed.rpt"
set clocks_rpt "build_outputs/clocks_${build_tag}_routed.rpt"
report_drc -file $drc_rpt
report_timing_summary -file $timing_rpt
report_utilization -file $util_rpt
report_clocks -file $clocks_rpt

set drc_error_count [drc_report_error_count $drc_rpt]

run_or_drc bitstream {
    write_bitstream -force $bit_file
}

set final_bit "final_bits/${build_tag}.bit"
file copy -force $bit_file $final_bit

set worst_setup [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set worst_hold  [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
set bit_sha [sha256_file $final_bit]

set summary "build_outputs/summary_${build_tag}.txt"
set fp [open $summary w]
puts $fp "BUILD_TAG=$build_tag"
puts $fp "MODE=$mode"
puts $fp "TOP=$top_module"
puts $fp "XDC=[file normalize $xdc_file]"
puts $fp "ACTIVE_IROM_PATH=[file normalize $active_irom]"
puts $fp "ACTIVE_IROM_SHA256=$irom_sha"
puts $fp "ACTIVE_IROM_FIRST8=$irom_first8"
puts $fp "SOURCE_IROM_PATH=[file normalize $source_irom]"
puts $fp "SOURCE_IROM_SHA256=$source_irom_sha"
puts $fp "GENERATED_IROM_SV=[file normalize $generated_irom_sv]"
puts $fp "GENERATED_IROM_WORDS=$irom_word_count"
puts $fp "IROM_IP_REFRESHED=$irom_ip_refreshed"
puts $fp "UART_TXDATA_ADDR=0x80200060"
puts $fp "UART_STATUS_ADDR=0x80200064"
puts $fp "UART_RXDATA_ADDR=0x80200068"
puts $fp "UART_CTRL_ADDR=0x8020006C"
puts $fp "UART_STATUS_BITS=bit0_tx_busy bit1_tx_ready bit2_rx_valid bit3_rx_overrun"
puts $fp "UART_PINS=i_uart_rx:D18 o_uart_tx:D17"
puts $fp "UART_FORMAT=115200 8N1 no_flow_control"
puts $fp "MONITOR_COMMANDS=? s l g r m d w v c t"
puts $fp "DRAM_ADDR_START=$dram_addr_start"
puts $fp "DRAM_ADDR_END=$dram_addr_end"
puts $fp "DRAM_ADDR_RANGE=$dram_addr_start-$dram_addr_end"
puts $fp "RAM_TEST_WORDS=$ram_test_words"
puts $fp "DUMP_WORDS=$dump_words"
puts $fp "RAM_TEST_PATTERNS=0x00000000 0xFFFFFFFF addr_xor_0x5A5A5A5A"
puts $fp "CNT_ADDR=0x80200050"
puts $fp "EXPECTED_BOOT=RV32 UART MONITOR, ? help, prompt"
puts $fp "RAM_PASS_LED=0x03030303"
puts $fp "RAM_PASS_SEG=0xA55A0001"
puts $fp "RAM_FAIL_LED=0x00000001"
puts $fp "RAM_FAIL_SEG=0xBAD00001"
puts $fp "WORST_SETUP_SLACK=$worst_setup"
puts $fp "WORST_HOLD_SLACK=$worst_hold"
puts $fp "DRC_ERROR_COUNT=$drc_error_count"
puts $fp "BIT_SHA256=$bit_sha"
puts $fp "BIT=[file normalize $bit_file]"
puts $fp "FINAL_BIT=[file normalize $final_bit]"
puts $fp "TIMING_REPORT=[file normalize $timing_rpt]"
puts $fp "UTIL_REPORT=[file normalize $util_rpt]"
puts $fp "DRC_REPORT=[file normalize $drc_rpt]"
puts $fp "CLOCKS_REPORT=[file normalize $clocks_rpt]"
close $fp

puts "UART_MONITOR_RAMTEST_MODE=$mode"
puts "UART_MONITOR_RAMTEST_BIT=[file normalize $bit_file]"
puts "UART_MONITOR_RAMTEST_FINAL_BIT=[file normalize $final_bit]"
puts "UART_MONITOR_RAMTEST_BIT_SHA256=$bit_sha"
puts "UART_MONITOR_RAMTEST_IROM_SHA256=$irom_sha"
puts "UART_MONITOR_RAMTEST_IROM_FIRST8=$irom_first8"
puts "UART_MONITOR_RAMTEST_WNS=$worst_setup"
puts "UART_MONITOR_RAMTEST_WHS=$worst_hold"
puts "UART_MONITOR_RAMTEST_DRC_ERROR_COUNT=$drc_error_count"
puts "UART_MONITOR_RAMTEST_DRAM_RANGE=$dram_addr_start-$dram_addr_end"
puts "UART_MONITOR_RAMTEST_WORDS=$ram_test_words"
puts "UART_MONITOR_RAMTEST_SUMMARY=[file normalize $summary]"
puts "UART_MONITOR_RAMTEST_DONE"
exit 0
