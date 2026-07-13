set project_dir "build_outputs/hdmi_colorbar_720p_debug_uart_project"
set project_name "hdmi_colorbar_720p_debug_uart"
set build_tag "HDMI_COLORBAR_720p60_debug_uart_200m_[clock format [clock seconds] -format {%Y%m%d_%H%M%S}]"
set bit_file "hdmi_colorbar_720p_debug_uart.bit"

file mkdir build_outputs
file mkdir final_bits

create_project $project_name $project_dir -part xc7k325tffg900-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [list \
    digital_twin.srcs/sources_1/new/hdmi_colorbar_720p_debug_uart_top.sv \
    digital_twin.srcs/sources_1/new/hdmi_debug_uart_reporter.sv \
    digital_twin.srcs/sources_1/new/uart_tx.sv \
    digital_twin.srcs/sources_1/new/hdmi_clock_gen_720p.sv \
    digital_twin.srcs/sources_1/new/hdmi_demo_720p.sv \
    digital_twin.srcs/sources_1/new/hdmi_out_7series.sv \
    digital_twin.srcs/sources_1/new/hdmi_test_pattern_720p.sv \
    digital_twin.srcs/sources_1/new/tmds_encoder.sv \
    digital_twin.srcs/sources_1/new/video_timing_1280x720.sv \
]

add_files -norecurse -fileset sources_1 $rtl_files
set_property file_type SystemVerilog [get_files $rtl_files]
add_files -norecurse -fileset constrs_1 digital_twin.srcs/constrs_1/new/hdmi_colorbar_720p_debug_uart.xdc
set_property top hdmi_colorbar_720p_debug_uart_top [current_fileset]
update_compile_order -fileset sources_1

proc dump_drc_and_exit {stage} {
    set rpt "build_outputs/hdmi_colorbar_720p_debug_uart_drc_${stage}.rpt"
    catch {report_drc -file $rpt}
    puts "HDMI_DEBUG_UART_FAILED_STAGE=$stage"
    puts "HDMI_DEBUG_UART_DRC_REPORT=[file normalize $rpt]"
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
        puts "HDMI_DEBUG_UART_ERROR=$result"
        dump_drc_and_exit $stage
    }
}

run_or_drc synth {
    synth_design -top hdmi_colorbar_720p_debug_uart_top -part xc7k325tffg900-2
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

set final_bit "final_bits/${build_tag}.bit"
file copy -force $bit_file $final_bit

set worst_setup [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set worst_hold  [get_property SLACK [get_timing_paths -max_paths 1 -hold]]

set summary "build_outputs/summary_${build_tag}.txt"
set fp [open $summary w]
puts $fp "BUILD_TAG=$build_tag"
puts $fp "TOP=hdmi_colorbar_720p_debug_uart_top"
puts $fp "VIDEO_MODE=1280x720@60"
puts $fp "INPUT_CLOCK_MODE=200m"
puts $fp "MMCM=CLKIN=200MHz DIVCLK=10 MULT=37.125 CLKOUT0_DIV=10 CLKOUT1_DIV=2"
puts $fp "PIXEL_CLK_MHZ=74.25"
puts $fp "TMDS_5X_CLK_MHZ=371.25"
puts $fp "UART=115200 8N1 on o_uart_tx/D17"
puts $fp "HPD_INPUT=hdmi_hpd/D29 LVCMOS33"
puts $fp "WORST_SETUP_SLACK=$worst_setup"
puts $fp "WORST_HOLD_SLACK=$worst_hold"
puts $fp "BIT=[file normalize $bit_file]"
puts $fp "FINAL_BIT=[file normalize $final_bit]"
puts $fp "TIMING_REPORT=[file normalize $timing_rpt]"
puts $fp "UTIL_REPORT=[file normalize $util_rpt]"
puts $fp "DRC_REPORT=[file normalize $drc_rpt]"
puts $fp "CLOCKS_REPORT=[file normalize $clocks_rpt]"
close $fp

puts "HDMI_DEBUG_UART_BIT=[file normalize $bit_file]"
puts "HDMI_DEBUG_UART_FINAL_BIT=[file normalize $final_bit]"
puts "HDMI_DEBUG_UART_SUMMARY=[file normalize $summary]"
puts "HDMI_DEBUG_UART_DONE"
exit 0
