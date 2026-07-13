set project_dir "build_outputs/cpu_hdmi_led_status_project"
set project_name "cpu_hdmi_led_status"
set build_tag "CPU_HDMI_LED_STATUS_720p60_200m_[clock format [clock seconds] -format {%Y%m%d_%H%M%S}]"
set bit_file "cpu_hdmi_led_status.bit"

file mkdir build_outputs
file mkdir final_bits

create_project $project_name $project_dir -part xc7k325tffg900-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_sv_files [list \
    digital_twin.srcs/sources_1/new/top_cpu_hdmi_led_status.sv \
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
    digital_twin.srcs/sources_1/imports/test_src/dram.coe \
]

set ip_files [list \
    digital_twin.srcs/sources_1/ip/IROM/IROM.xci \
]

add_files -norecurse -fileset sources_1 $rtl_sv_files
add_files -norecurse -fileset sources_1 $rtl_v_files
add_files -norecurse -fileset sources_1 $memory_files
add_files -norecurse -fileset sources_1 $ip_files
set_property file_type SystemVerilog [get_files $rtl_sv_files]

add_files -norecurse -fileset constrs_1 digital_twin.srcs/constrs_1/new/cpu_hdmi_led_status_only.xdc
set_property top top_cpu_hdmi_led_status [current_fileset]

update_compile_order -fileset sources_1

set ips [get_ips -quiet]
if {[llength $ips] > 0} {
    generate_target all $ips
}

proc dump_drc_and_exit {stage} {
    set rpt "build_outputs/cpu_hdmi_led_status_drc_${stage}.rpt"
    catch {report_drc -file $rpt}
    puts "CPU_HDMI_LED_STATUS_FAILED_STAGE=$stage"
    puts "CPU_HDMI_LED_STATUS_DRC_REPORT=[file normalize $rpt]"
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
        puts "CPU_HDMI_LED_STATUS_ERROR=$result"
        dump_drc_and_exit $stage
    }
}

run_or_drc synth {
    synth_design -top top_cpu_hdmi_led_status -part xc7k325tffg900-2
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
puts $fp "TOP=top_cpu_hdmi_led_status"
puts $fp "VIDEO_MODE=1280x720@60"
puts $fp "INPUT_CLOCK_MODE=200m"
puts $fp "CPU_CLOCK_MHZ=200"
puts $fp "CPU_CLOCK_MMCM=CLKIN=200MHz DIVCLK=1 MULT=5 CLKOUT0_DIV=20 CLKOUT1_DIV=5"
puts $fp "HDMI_MMCM=CLKIN=200MHz DIVCLK=10 MULT=37.125 CLKOUT1_DIV=2"
puts $fp "PIXEL_CLK_MHZ=74.25"
puts $fp "SERIAL_CLK_MHZ=371.25"
puts $fp "HDMI_SERIALIZER=hdmi_out_7series_ref"
puts $fp "HDMI_PIXEL_CLOCK_BUFFER=BUFR_DIVIDE_5_FROM_SERIAL_CLK"
puts $fp "SYSCLK_TO_HDMI_CMT_ROUTE=ANY_CMT_COLUMN"
puts $fp "VIRTUAL_LED=cpu_led_value[31:0] on board LED pins, LVCMOS33"
puts $fp "VIRTUAL_SEG_PHYSICAL_PORTS=not present"
puts $fp "UART_CPU_TX=115200 8N1 on o_uart_tx/D17"
puts $fp "UART_TWIN=9600 8N1 on i_uart_rx/D18 and o_uart_tx/D17"
puts $fp "WORST_SETUP_SLACK=$worst_setup"
puts $fp "WORST_HOLD_SLACK=$worst_hold"
puts $fp "BIT=[file normalize $bit_file]"
puts $fp "FINAL_BIT=[file normalize $final_bit]"
puts $fp "TIMING_REPORT=[file normalize $timing_rpt]"
puts $fp "UTIL_REPORT=[file normalize $util_rpt]"
puts $fp "DRC_REPORT=[file normalize $drc_rpt]"
puts $fp "CLOCKS_REPORT=[file normalize $clocks_rpt]"
close $fp

puts "CPU_HDMI_LED_STATUS_BIT=[file normalize $bit_file]"
puts "CPU_HDMI_LED_STATUS_FINAL_BIT=[file normalize $final_bit]"
puts "CPU_HDMI_LED_STATUS_SUMMARY=[file normalize $summary]"
puts "CPU_HDMI_LED_STATUS_DONE"
exit 0
