set variant "withMext"
if {[info exists argv] && [llength $argv] > 0} {
    set variant [lindex $argv 0]
}
if {![regexp {^(withMext|withoutMext)$} $variant]} {
    error "Unsupported variant '$variant'. Use withMext or withoutMext."
}
set panel_mode "status"
if {[info exists argv] && [llength $argv] > 1} {
    set panel_mode [lindex $argv 1]
}
if {![regexp {^(status|debug)$} $panel_mode]} {
    error "Unsupported panel mode '$panel_mode'. Use status or debug."
}

set variant_upper [string toupper $variant]
set project_dir "build_outputs/cpu_hdmi_ls_${variant}_project"
set project_name "cpu_hdmi_ls_${variant}"
set top_module "top_cpu_hdmi_led_seg_status"
set bit_suffix ""
set build_debug_tag ""
if {$panel_mode eq "debug"} {
    set top_module "top_cpu_hdmi_led_seg_debug_status"
    set bit_suffix "_debug"
    set build_debug_tag "_DEBUG"
}
set build_tag "CPU_HDMI_LED_SEG_STATUS_${variant}_v2${build_debug_tag}_720p60_200m_[clock format [clock seconds] -format {%Y%m%d_%H%M%S}]"
set bit_file "cpu_hdmi_led_seg_status_${variant}_v2${bit_suffix}.bit"

set preferred_irom "digital_twin.srcs/file_coe/coe/${variant}/demo/irom-v2.coe"
set external_irom  "E:/jyd2026/${variant}/demo/irom-v2.coe"
set fallback_irom  "digital_twin.srcs/file_coe/coe/${variant}/irom.coe"
set active_irom    "digital_twin.srcs/sources_1/imports/test_src/irom.coe"

set preferred_dram "digital_twin.srcs/file_coe/coe/${variant}/demo/dram.coe"
set external_dram  "E:/jyd2026/${variant}/demo/dram.coe"
set fallback_dram  "digital_twin.srcs/file_coe/coe/${variant}/dram.coe"
set active_dram    "digital_twin.srcs/sources_1/imports/test_src/dram.coe"

set irom_xci "digital_twin.srcs/sources_1/ip/IROM/IROM.xci"
set dram_xci "digital_twin.srcs/sources_1/ip/DRAM/DRAM.xci"
set generated_irom_sv "build_outputs/generated_irom_withMext_v2.sv"
set generated_dram_sv "build_outputs/generated_dram_driver_withMext_v2.sv"

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

proc pick_existing_file {label candidates} {
    foreach candidate $candidates {
        if {[file exists $candidate]} {
            puts "${label}_SOURCE_SELECTED=[file normalize $candidate]"
            return $candidate
        }
    }
    error "Cannot find $label. Tried: $candidates"
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
        error "No ROM/RAM words parsed from $coe_path"
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

proc hex_byte {word byte_index} {
    set start [expr {6 - (2 * $byte_index)}]
    set end [expr {$start + 1}]
    return [string range $word $start $end]
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

proc write_dram_driver_sv_from_words {words sv_path} {
    if {[llength $words] > 65536} {
        error "DRAM COE has [llength $words] words, exceeds 65536"
    }

    file mkdir [file dirname $sv_path]
    set out [open $sv_path w]
    puts $out {`timescale 1ns / 1ps}
    puts $out {}
    puts $out {module dram_driver(}
    puts $out {    input  logic         clk,}
    puts $out {    input  logic [17:0]  perip_addr,}
    puts $out {    input  logic [31:0]  perip_wdata,}
    puts $out {    input  logic [1:0]   perip_mask,}
    puts $out {    input  logic         dram_wen,}
    puts $out {    output logic [31:0]  perip_rdata}
    puts $out {);}
    puts $out {    localparam int DRAM_DEPTH = 65536;}
    puts $out {}
    puts $out {    logic [15:0] dram_addr;}
    puts $out {    logic [1:0]  offset;}
    puts $out {    logic [7:0] lane0_wdata, lane1_wdata, lane2_wdata, lane3_wdata;}
    puts $out {    logic       lane0_wen, lane1_wen, lane2_wen, lane3_wen;}
    puts $out {    (* ram_style = "block" *) logic [7:0] dram_lane0 [0:DRAM_DEPTH - 1];}
    puts $out {    (* ram_style = "block" *) logic [7:0] dram_lane1 [0:DRAM_DEPTH - 1];}
    puts $out {    (* ram_style = "block" *) logic [7:0] dram_lane2 [0:DRAM_DEPTH - 1];}
    puts $out {    (* ram_style = "block" *) logic [7:0] dram_lane3 [0:DRAM_DEPTH - 1];}
    puts $out {}
    puts $out {    assign dram_addr = perip_addr[17:2];}
    puts $out {    assign offset = perip_addr[1:0];}
    puts $out {}
    puts $out {    integer i;}
    puts $out {    initial begin}
    puts $out {`ifndef SYNTHESIS}
    puts $out {        for (i = 0; i < DRAM_DEPTH; i = i + 1) begin}
    puts $out {            dram_lane0[i] = 8'h00;}
    puts $out {            dram_lane1[i] = 8'h00;}
    puts $out {            dram_lane2[i] = 8'h00;}
    puts $out {            dram_lane3[i] = 8'h00;}
    puts $out {        end}
    puts $out {`endif}
    puts $out {}
    puts $out {        // Init words generated from active withMext v2 DRAM COE.}
    for {set idx 0} {$idx < [llength $words]} {incr idx} {
        set word [lindex $words $idx]
        puts $out [format "        dram_lane0\[16'd%d\] = 8'h%s;" $idx [hex_byte $word 0]]
        puts $out [format "        dram_lane1\[16'd%d\] = 8'h%s;" $idx [hex_byte $word 1]]
        puts $out [format "        dram_lane2\[16'd%d\] = 8'h%s;" $idx [hex_byte $word 2]]
        puts $out [format "        dram_lane3\[16'd%d\] = 8'h%s;" $idx [hex_byte $word 3]]
        puts $out {}
    }
    puts $out {    end}
    puts $out {}
    puts $out {    always_comb begin}
    puts $out {        lane0_wdata = perip_wdata[7:0];}
    puts $out {        lane1_wdata = perip_wdata[15:8];}
    puts $out {        lane2_wdata = perip_wdata[23:16];}
    puts $out {        lane3_wdata = perip_wdata[31:24];}
    puts $out {        lane0_wen = 1'b0;}
    puts $out {        lane1_wen = 1'b0;}
    puts $out {        lane2_wen = 1'b0;}
    puts $out {        lane3_wen = 1'b0;}
    puts $out {}
    puts $out {        if (dram_wen) begin}
    puts $out {            unique case (perip_mask)}
    puts $out {                2'b10: begin}
    puts $out {                    lane0_wen = 1'b1;}
    puts $out {                    lane1_wen = 1'b1;}
    puts $out {                    lane2_wen = 1'b1;}
    puts $out {                    lane3_wen = 1'b1;}
    puts $out {                end}
    puts $out {                2'b01: begin}
    puts $out {                    if (!offset[1]) begin}
    puts $out {                        lane0_wen = 1'b1;}
    puts $out {                        lane1_wen = 1'b1;}
    puts $out {                    end else begin}
    puts $out {                        lane2_wen = 1'b1;}
    puts $out {                        lane3_wen = 1'b1;}
    puts $out {                        lane2_wdata = perip_wdata[7:0];}
    puts $out {                        lane3_wdata = perip_wdata[15:8];}
    puts $out {                    end}
    puts $out {                end}
    puts $out {                2'b00: begin}
    puts $out {                    lane0_wdata = perip_wdata[7:0];}
    puts $out {                    lane1_wdata = perip_wdata[7:0];}
    puts $out {                    lane2_wdata = perip_wdata[7:0];}
    puts $out {                    lane3_wdata = perip_wdata[7:0];}
    puts $out {                    unique case (offset)}
    puts $out {                        2'b00: lane0_wen = 1'b1;}
    puts $out {                        2'b01: lane1_wen = 1'b1;}
    puts $out {                        2'b10: lane2_wen = 1'b1;}
    puts $out {                        2'b11: lane3_wen = 1'b1;}
    puts $out {                    endcase}
    puts $out {                end}
    puts $out {                default: begin}
    puts $out {                    lane0_wen = 1'b1;}
    puts $out {                    lane1_wen = 1'b1;}
    puts $out {                    lane2_wen = 1'b1;}
    puts $out {                    lane3_wen = 1'b1;}
    puts $out {                end}
    puts $out {            endcase}
    puts $out {        end}
    puts $out {    end}
    puts $out {}
    puts $out {    always_ff @(posedge clk) begin}
    puts $out {        if (lane0_wen) dram_lane0[dram_addr] <= lane0_wdata;}
    puts $out {        if (lane1_wen) dram_lane1[dram_addr] <= lane1_wdata;}
    puts $out {        if (lane2_wen) dram_lane2[dram_addr] <= lane2_wdata;}
    puts $out {        if (lane3_wen) dram_lane3[dram_addr] <= lane3_wdata;}
    puts $out "        perip_rdata <= {dram_lane3\[dram_addr\], dram_lane2\[dram_addr\], dram_lane1\[dram_addr\], dram_lane0\[dram_addr\]};"
    puts $out {    end}
    puts $out {endmodule}
    close $out
}

proc refresh_memory_ip_outputs {irom_xci dram_xci} {
    set ip_project_dir "build_outputs/withMext_v2_ip_refresh_project"
    create_project withMext_v2_ip_refresh $ip_project_dir -part xc7k325tffg900-2 -force

    set irom_refreshed 0
    set dram_refreshed 0

    if {[file exists $irom_xci]} {
        add_files -norecurse $irom_xci
        generate_target all [get_files $irom_xci]
        export_ip_user_files -of_objects [get_files $irom_xci] -no_script -sync -force -quiet
        set irom_refreshed 1
    }

    if {[file exists $dram_xci]} {
        add_files -norecurse $dram_xci
        generate_target all [get_files $dram_xci]
        export_ip_user_files -of_objects [get_files $dram_xci] -no_script -sync -force -quiet
        set dram_refreshed 1
    }

    close_project
    puts "IROM_IP_REFRESHED=$irom_refreshed"
    puts "DRAM_IP_REFRESHED=$dram_refreshed"
    return [list $irom_refreshed $dram_refreshed]
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

proc drc_report_has_rule {rpt rule_prefix} {
    if {![file exists $rpt]} {
        return -1
    }
    set fp [open $rpt r]
    set text [read $fp]
    close $fp
    return [regexp -nocase "\\|\\s*$rule_prefix" $text]
}

set source_irom [pick_existing_file IROM [list $preferred_irom $external_irom $fallback_irom]]
set source_dram [pick_existing_file DRAM [list $preferred_dram $external_dram $fallback_dram]]

foreach forbidden [list "smoke" "uart-hello" "irom-uart" "z-light"] {
    if {[string match -nocase "*$forbidden*" $source_irom]} {
        error "Refusing to build withMext v2 from non-v2 IROM: $source_irom"
    }
}

file mkdir build_outputs
file mkdir final_bits

file copy -force $source_irom $active_irom
file copy -force $source_dram $active_dram

set irom_sha [sha256_file $active_irom]
set dram_sha [sha256_file $active_dram]
set source_irom_sha [sha256_file $source_irom]
set source_dram_sha [sha256_file $source_dram]
set irom_words [parse_coe_words $active_irom]
set dram_words [parse_coe_words $active_dram]
set irom_first8 [first_words_string $irom_words 8]
set dram_first8 [first_words_string $dram_words 8]

write_irom_sv_from_words $irom_words $generated_irom_sv
write_dram_driver_sv_from_words $dram_words $generated_dram_sv
set irom_word_count [llength $irom_words]
set dram_word_count [llength $dram_words]

puts "ACTIVE_IROM_PATH=[file normalize $active_irom]"
puts "ACTIVE_IROM_SHA256=$irom_sha"
puts "ACTIVE_IROM_FIRST8=$irom_first8"
puts "SOURCE_IROM_PATH=[file normalize $source_irom]"
puts "SOURCE_IROM_SHA256=$source_irom_sha"
puts "ACTIVE_DRAM_PATH=[file normalize $active_dram]"
puts "ACTIVE_DRAM_SHA256=$dram_sha"
puts "ACTIVE_DRAM_FIRST8=$dram_first8"
puts "SOURCE_DRAM_PATH=[file normalize $source_dram]"
puts "SOURCE_DRAM_SHA256=$source_dram_sha"
puts "GENERATED_IROM_SV=[file normalize $generated_irom_sv]"
puts "GENERATED_IROM_WORDS=$irom_word_count"
puts "GENERATED_DRAM_DRIVER_SV=[file normalize $generated_dram_sv]"
puts "GENERATED_DRAM_WORDS=$dram_word_count"

set refresh_status [refresh_memory_ip_outputs $irom_xci $dram_xci]
set irom_ip_refreshed [lindex $refresh_status 0]
set dram_ip_refreshed [lindex $refresh_status 1]

create_project $project_name $project_dir -part xc7k325tffg900-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_sv_files [list \
    digital_twin.srcs/sources_1/new/top_cpu_hdmi_led_seg_status.sv \
    digital_twin.srcs/sources_1/new/top_cpu_hdmi_led_seg_debug_status.sv \
    build_outputs/generated_irom_withMext_v2.sv \
    build_outputs/generated_dram_driver_withMext_v2.sv \
    digital_twin.srcs/sources_1/new/cpu_clock_gen_status.sv \
    digital_twin.srcs/sources_1/new/hdmi_clock_gen_720p_ref.sv \
    digital_twin.srcs/sources_1/new/hdmi_status_panel.sv \
    digital_twin.srcs/sources_1/new/hdmi_text_overlay.sv \
    digital_twin.srcs/sources_1/new/hdmi_debug_panel.sv \
    digital_twin.srcs/sources_1/new/hdmi_debug_text_overlay.sv \
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
    digital_twin.srcs/sources_1/imports/test_src/dram.coe \
    $source_irom \
    $source_dram \
]

add_files -norecurse -fileset sources_1 $rtl_sv_files
add_files -norecurse -fileset sources_1 $rtl_v_files
add_files -norecurse -fileset sources_1 $memory_files
set_property file_type SystemVerilog [get_files $rtl_sv_files]

add_files -norecurse -fileset constrs_1 digital_twin.srcs/constrs_1/new/cpu_hdmi_led_seg_status_only.xdc
set_property top $top_module [current_fileset]
puts "VERILOG_DEFINE=[get_property verilog_define [current_fileset]]"

update_compile_order -fileset sources_1

proc dump_drc_and_exit {stage} {
    set rpt "build_outputs/cpu_hdmi_led_seg_status_withMext_v2_drc_${stage}.rpt"
    catch {report_drc -file $rpt}
    puts "CPU_HDMI_LED_SEG_STATUS_WITHMEXT_V2_FAILED_STAGE=$stage"
    puts "CPU_HDMI_LED_SEG_STATUS_WITHMEXT_V2_DRC_REPORT=[file normalize $rpt]"
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
        puts "CPU_HDMI_LED_SEG_STATUS_WITHMEXT_V2_ERROR=$result"
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
set drc_has_bivc [drc_report_has_rule $drc_rpt "BIVC"]
set drc_has_nstd [drc_report_has_rule $drc_rpt "NSTD"]
set drc_has_ucio [drc_report_has_rule $drc_rpt "UCIO"]

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
puts $fp "VARIANT=$variant"
puts $fp "PANEL_MODE=$panel_mode"
puts $fp "TOP=$top_module"
puts $fp "VERILOG_DEFINE=[get_property verilog_define [current_fileset]]"
puts $fp "VIDEO_MODE=1280x720@60"
puts $fp "INPUT_CLOCK_MODE=200m"
puts $fp "CPU_CLOCK_MHZ=200"
puts $fp "CPU_CLOCK_MMCM=CLKIN=200MHz DIVCLK=1 MULT=5 CLKOUT0_DIV=20 CLKOUT1_DIV=5"
puts $fp "HDMI_MMCM=CLKIN=200MHz DIVCLK=10 MULT=37.125 CLKOUT1_DIV=2"
puts $fp "PIXEL_CLK_MHZ=74.25"
puts $fp "SERIAL_CLK_MHZ=371.25"
puts $fp "HDMI_SERIALIZER=hdmi_out_7series_ref"
puts $fp "ACTIVE_IROM_PATH=[file normalize $active_irom]"
puts $fp "ACTIVE_IROM_SHA256=$irom_sha"
puts $fp "ACTIVE_IROM_FIRST8=$irom_first8"
puts $fp "SOURCE_IROM_PATH=[file normalize $source_irom]"
puts $fp "SOURCE_IROM_SHA256=$source_irom_sha"
puts $fp "ACTIVE_DRAM_PATH=[file normalize $active_dram]"
puts $fp "ACTIVE_DRAM_SHA256=$dram_sha"
puts $fp "ACTIVE_DRAM_FIRST8=$dram_first8"
puts $fp "SOURCE_DRAM_PATH=[file normalize $source_dram]"
puts $fp "SOURCE_DRAM_SHA256=$source_dram_sha"
puts $fp "GENERATED_IROM_SV=[file normalize $generated_irom_sv]"
puts $fp "GENERATED_IROM_WORDS=$irom_word_count"
puts $fp "GENERATED_DRAM_DRIVER_SV=[file normalize $generated_dram_sv]"
puts $fp "GENERATED_DRAM_WORDS=$dram_word_count"
puts $fp "IROM_IP_REFRESHED=$irom_ip_refreshed"
puts $fp "DRAM_IP_REFRESHED=$dram_ip_refreshed"
puts $fp "IROM_CONFIRMED_NOT_SMOKE_OR_UART=1"
puts $fp "VIRTUAL_LED=cpu_led_value[31:0] on board LED pins, LVCMOS33"
puts $fp "HDMI_SEG_FIELD=student_top raw virtual_seg_value[31:0]"
puts $fp "VIRTUAL_SEG=student_top display_seg scanned output on board SEG pins, LVCMOS33"
puts $fp "UART_CPU_TX=115200 8N1 on o_uart_tx/D17"
puts $fp "UART_TWIN=9600 8N1 on i_uart_rx/D18 and o_uart_tx/D17"
puts $fp "WORST_SETUP_SLACK=$worst_setup"
puts $fp "WORST_HOLD_SLACK=$worst_hold"
puts $fp "DRC_ERROR_COUNT=$drc_error_count"
puts $fp "DRC_HAS_BIVC=$drc_has_bivc"
puts $fp "DRC_HAS_NSTD=$drc_has_nstd"
puts $fp "DRC_HAS_UCIO=$drc_has_ucio"
puts $fp "BIT_SHA256=$bit_sha"
puts $fp "BIT=[file normalize $bit_file]"
puts $fp "FINAL_BIT=[file normalize $final_bit]"
puts $fp "TIMING_REPORT=[file normalize $timing_rpt]"
puts $fp "UTIL_REPORT=[file normalize $util_rpt]"
puts $fp "DRC_REPORT=[file normalize $drc_rpt]"
puts $fp "CLOCKS_REPORT=[file normalize $clocks_rpt]"
close $fp

puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_BIT=[file normalize $bit_file]"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_FINAL_BIT=[file normalize $final_bit]"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_BIT_SHA256=$bit_sha"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_IROM_SHA256=$irom_sha"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_IROM_FIRST8=$irom_first8"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_DRAM_SHA256=$dram_sha"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_DRAM_FIRST8=$dram_first8"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_WNS=$worst_setup"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_WHS=$worst_hold"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_DRC_ERROR_COUNT=$drc_error_count"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_DRC_HAS_BIVC=$drc_has_bivc"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_DRC_HAS_NSTD=$drc_has_nstd"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_DRC_HAS_UCIO=$drc_has_ucio"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_IROM_IP_REFRESHED=$irom_ip_refreshed"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_DRAM_IP_REFRESHED=$dram_ip_refreshed"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_SUMMARY=[file normalize $summary]"
puts "CPU_HDMI_LED_SEG_STATUS_${variant_upper}_V2_DONE"
exit 0
