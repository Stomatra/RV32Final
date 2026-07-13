set project_dir "build_outputs/cpu_hdmi_ls_mmio_smoke_project"
set project_name "cpu_hdmi_ls_mmio_smoke"
set build_tag "CPU_HDMI_LED_SEG_STATUS_MMIO_SMOKE_720p60_200m_[clock format [clock seconds] -format {%Y%m%d_%H%M%S}]"
set bit_file "cpu_hdmi_led_seg_status_mmio_smoke.bit"

set source_irom "digital_twin.srcs/sources_1/imports/test_src/irom-mmio-smoke.coe"
set active_irom "digital_twin.srcs/sources_1/imports/test_src/irom.coe"
set irom_xci "digital_twin.srcs/sources_1/ip/IROM/IROM.xci"
set generated_irom_sv "build_outputs/generated_irom_mmio_smoke.sv"

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

proc write_irom_sv_from_coe {coe_path sv_path} {
    set in [open $coe_path r]
    set text [read $in]
    close $in

    regsub -all {\r} $text "" text
    set marker "memory_initialization_vector="
    set marker_pos [string first $marker $text]
    if {$marker_pos < 0} {
        error "Cannot find memory_initialization_vector in $coe_path"
    }
    set vector_text [string range $text [expr {$marker_pos + [string length $marker]}] end]
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
    if {[llength $words] > 4096} {
        error "IROM COE has [llength $words] words, exceeds 4096"
    }

    file mkdir [file dirname $sv_path]
    set out [open $sv_path w]
    puts $out "`timescale 1ns / 1ps"
    puts $out ""
    puts $out "module IROM ("
    puts $out "    input  logic \[11:0\] a,"
    puts $out "    output logic \[31:0\] spo"
    puts $out ");"
    puts $out "    (* rom_style = \"distributed\" *) logic \[31:0\] rom \[0:4095\];"
    puts $out "    integer i;"
    puts $out ""
    puts $out "    initial begin"
    puts $out "        for (i = 0; i < 4096; i = i + 1) begin"
    puts $out "            rom\[i\] = 32'h00000000;"
    puts $out "        end"
    for {set idx 0} {$idx < [llength $words]} {incr idx} {
        puts $out [format "        rom\[%d\] = 32'h%s;" $idx [lindex $words $idx]]
    }
    puts $out "    end"
    puts $out ""
    puts $out "    always_comb begin"
    puts $out "        spo = rom\[a\];"
    puts $out "    end"
    puts $out ""
    puts $out "endmodule"
    close $out

    return [llength $words]
}

proc refresh_irom_ip_outputs {irom_xci} {
    if {![file exists $irom_xci]} {
        puts "IROM_IP_REFRESH_SKIPPED=missing_xci"
        return
    }

    set ip_project_dir "build_outputs/irom_mmio_smoke_ip_refresh_project"
    create_project irom_mmio_smoke_ip_refresh $ip_project_dir -part xc7k325tffg900-2 -force
    add_files -norecurse $irom_xci
    generate_target all [get_files $irom_xci]
    export_ip_user_files -of_objects [get_files $irom_xci] -no_script -sync -force -quiet
    close_project
    puts "IROM_IP_REFRESHED=1"
}

if {![file exists $source_irom]} {
    error "Cannot find MMIO smoke IROM: $source_irom"
}

file mkdir build_outputs
file mkdir final_bits

file copy -force $source_irom $active_irom
set irom_sha [sha256_file $active_irom]
set source_irom_sha [sha256_file $source_irom]
set irom_word_count [write_irom_sv_from_coe $active_irom $generated_irom_sv]
puts "ACTIVE_IROM_PATH=[file normalize $active_irom]"
puts "ACTIVE_IROM_SHA256=$irom_sha"
puts "SOURCE_IROM_PATH=[file normalize $source_irom]"
puts "SOURCE_IROM_SHA256=$source_irom_sha"
puts "GENERATED_IROM_SV=[file normalize $generated_irom_sv]"
puts "GENERATED_IROM_WORDS=$irom_word_count"

refresh_irom_ip_outputs $irom_xci

create_project $project_name $project_dir -part xc7k325tffg900-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_sv_files [list \
    digital_twin.srcs/sources_1/new/top_cpu_hdmi_led_seg_status.sv \
    build_outputs/generated_irom_mmio_smoke.sv \
    digital_twin.srcs/sources_1/new/cpu_clock_gen_status.sv \
    digital_twin.srcs/sources_1/new/hdmi_clock_gen_720p_ref.sv \
    digital_twin.srcs/sources_1/new/hdmi_status_panel.sv \
    digital_twin.srcs/sources_1/new/hdmi_text_overlay.sv \
    digital_twin.srcs/sources_1/new/font_rom_8x16.sv \
    digital_twin.srcs/sources_1/new/hdmi_out_7series_ref.sv \
    digital_twin.srcs/sources_1/new/tmds_encoder.sv \
    digital_twin.srcs/sources_1/new/video_timing_1280x720.sv \
    digital_twin.srcs/sources_1/new/student_top.sv \
    digital_twin.srcs/sources_1/new/myCPU.sv \
    digital_twin.srcs/sources_1/new/perip_bridge.sv \
    digital_twin.srcs/sources_1/new/counter.sv \
    digital_twin.srcs/sources_1/new/display_seg.sv \
    digital_twin.srcs/sources_1/new/seg7.sv \
    digital_twin.srcs/sources_1/new/dram_driver.sv \
    digital_twin.srcs/sources_1/new/uart.sv \
    digital_twin.srcs/sources_1/new/uart_tx.sv \
    digital_twin.srcs/sources_1/new/uart_rx.sv \
    digital_twin.srcs/sources_1/new/twin_controller.sv \
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

set rtl_v_files [list \
    digital_twin.srcs/sources_1/imports/new/MuxKey.v \
    digital_twin.srcs/sources_1/imports/new/MuxKeyInternal.v \
]

set memory_files [list \
    digital_twin.srcs/sources_1/imports/test_src/irom.coe \
    digital_twin.srcs/sources_1/imports/test_src/irom-mmio-smoke.coe \
    digital_twin.srcs/sources_1/imports/test_src/dram.coe \
]

add_files -norecurse -fileset sources_1 $rtl_sv_files
add_files -norecurse -fileset sources_1 $rtl_v_files
add_files -norecurse -fileset sources_1 $memory_files
set_property file_type SystemVerilog [get_files $rtl_sv_files]

add_files -norecurse -fileset constrs_1 digital_twin.srcs/constrs_1/new/cpu_hdmi_led_seg_status_only.xdc
set_property top top_cpu_hdmi_led_seg_status [current_fileset]

update_compile_order -fileset sources_1

proc dump_drc_and_exit {stage} {
    set rpt "build_outputs/cpu_hdmi_led_seg_status_mmio_smoke_drc_${stage}.rpt"
    catch {report_drc -file $rpt}
    puts "CPU_HDMI_LED_SEG_STATUS_MMIO_SMOKE_FAILED_STAGE=$stage"
    puts "CPU_HDMI_LED_SEG_STATUS_MMIO_SMOKE_DRC_REPORT=[file normalize $rpt]"
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
        puts "CPU_HDMI_LED_SEG_STATUS_MMIO_SMOKE_ERROR=$result"
        dump_drc_and_exit $stage
    }
}

run_or_drc synth {
    synth_design -top top_cpu_hdmi_led_seg_status -part xc7k325tffg900-2
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

run_or_drc bitstream {
    write_bitstream -force $bit_file
}

set final_bit "final_bits/$bit_file"
file copy -force $bit_file $final_bit

set worst_setup [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set worst_hold [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
set bit_sha [sha256_file $final_bit]

set summary "build_outputs/summary_${build_tag}.txt"
set fp [open $summary w]
puts $fp "BUILD_TAG=$build_tag"
puts $fp "TOP=top_cpu_hdmi_led_seg_status"
puts $fp "VIDEO_MODE=1280x720@60"
puts $fp "INPUT_CLOCK_MODE=200m"
puts $fp "CPU_CLOCK_MHZ=200"
puts $fp "HDMI_SERIALIZER=hdmi_out_7series_ref"
puts $fp "ACTIVE_IROM_PATH=[file normalize $active_irom]"
puts $fp "ACTIVE_IROM_SHA256=$irom_sha"
puts $fp "SOURCE_IROM_PATH=[file normalize $source_irom]"
puts $fp "SOURCE_IROM_SHA256=$source_irom_sha"
puts $fp "GENERATED_IROM_SV=[file normalize $generated_irom_sv]"
puts $fp "GENERATED_IROM_WORDS=$irom_word_count"
puts $fp "MMIO_SMOKE_EXPECTED_LED=0x00000010"
puts $fp "MMIO_SMOKE_EXPECTED_SEG=0x12345678"
puts $fp "VIRTUAL_LED=cpu_led_value[31:0] on board LED pins, LVCMOS33"
puts $fp "HDMI_SEG_FIELD=student_top raw virtual_seg_value[31:0]"
puts $fp "VIRTUAL_SEG=student_top display_seg scanned output on board SEG pins, LVCMOS33"
puts $fp "WORST_SETUP_SLACK=$worst_setup"
puts $fp "WORST_HOLD_SLACK=$worst_hold"
puts $fp "BIT_SHA256=$bit_sha"
puts $fp "BIT=[file normalize $bit_file]"
puts $fp "FINAL_BIT=[file normalize $final_bit]"
puts $fp "TIMING_REPORT=[file normalize $timing_rpt]"
puts $fp "UTIL_REPORT=[file normalize $util_rpt]"
puts $fp "DRC_REPORT=[file normalize $drc_rpt]"
puts $fp "CLOCKS_REPORT=[file normalize $clocks_rpt]"
close $fp

puts "CPU_HDMI_LED_SEG_STATUS_MMIO_SMOKE_BIT=[file normalize $bit_file]"
puts "CPU_HDMI_LED_SEG_STATUS_MMIO_SMOKE_FINAL_BIT=[file normalize $final_bit]"
puts "CPU_HDMI_LED_SEG_STATUS_MMIO_SMOKE_BIT_SHA256=$bit_sha"
puts "CPU_HDMI_LED_SEG_STATUS_MMIO_SMOKE_IROM_SHA256=$irom_sha"
puts "CPU_HDMI_LED_SEG_STATUS_MMIO_SMOKE_WNS=$worst_setup"
puts "CPU_HDMI_LED_SEG_STATUS_MMIO_SMOKE_WHS=$worst_hold"
puts "CPU_HDMI_LED_SEG_STATUS_MMIO_SMOKE_DRC_REPORT=[file normalize $drc_rpt]"
puts "CPU_HDMI_LED_SEG_STATUS_MMIO_SMOKE_SUMMARY=[file normalize $summary]"
puts "CPU_HDMI_LED_SEG_STATUS_MMIO_SMOKE_DONE"
exit 0
