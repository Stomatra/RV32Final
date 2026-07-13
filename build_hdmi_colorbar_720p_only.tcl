if {[llength $argv] > 0} {
    set input_clock_mode [string tolower [lindex $argv 0]]
} else {
    set input_clock_mode "125m"
}

if {$input_clock_mode eq "100" || $input_clock_mode eq "100mhz"} {
    set input_clock_mode "100m"
}
if {$input_clock_mode eq "125" || $input_clock_mode eq "125mhz"} {
    set input_clock_mode "125m"
}

if {$input_clock_mode eq "100m"} {
    set top_module "hdmi_colorbar_720p_top_100m"
    set xdc_file "digital_twin.srcs/constrs_1/new/hdmi_colorbar_720p_only_100m.xdc"
    set clock_note "100 MHz input, exact 74.25/371.25 MHz"
    set pixel_clk_mhz "74.25"
    set tmds_5x_clk_mhz "371.25"
    set mmcm_note "CLKIN=100MHz DIVCLK=5 MULT=37.125 CLKOUT0_DIV=10 CLKOUT1_DIV=2"
} elseif {$input_clock_mode eq "125m"} {
    set top_module "hdmi_colorbar_720p_top"
    set xdc_file "digital_twin.srcs/constrs_1/new/hdmi_colorbar_720p_only.xdc"
    set clock_note "125 MHz input, near-standard 74.21875/371.09375 MHz"
    set pixel_clk_mhz "74.21875"
    set tmds_5x_clk_mhz "371.09375"
    set mmcm_note "CLKIN=125MHz DIVCLK=8 MULT=47.500 CLKOUT0_DIV=10 CLKOUT1_DIV=2"
} else {
    puts "Usage: vivado -mode batch -source build_hdmi_colorbar_720p_only.tcl -tclargs 125m|100m"
    exit 1
}

set project_dir "build_outputs/hdmi_colorbar_720p_only_${input_clock_mode}_project"
set project_name "hdmi_colorbar_720p_only_${input_clock_mode}"
set build_tag "HDMI_COLORBAR_ONLY_1280x720_60_${input_clock_mode}_[clock format [clock seconds] -format {%Y%m%d_%H%M%S}]"
set bit_file "hdmi_colorbar_720p_only_${input_clock_mode}.bit"

file mkdir build_outputs
file mkdir final_bits

create_project $project_name $project_dir -part xc7k325tffg900-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [list \
    digital_twin.srcs/sources_1/new/hdmi_colorbar_720p_top.sv \
    digital_twin.srcs/sources_1/new/hdmi_colorbar_720p_top_100m.sv \
    digital_twin.srcs/sources_1/new/hdmi_clock_gen_720p.sv \
    digital_twin.srcs/sources_1/new/hdmi_demo_720p.sv \
    digital_twin.srcs/sources_1/new/hdmi_out_7series.sv \
    digital_twin.srcs/sources_1/new/hdmi_test_pattern_720p.sv \
    digital_twin.srcs/sources_1/new/tmds_encoder.sv \
    digital_twin.srcs/sources_1/new/video_timing_1280x720.sv \
]

add_files -norecurse -fileset sources_1 $rtl_files
set_property file_type SystemVerilog [get_files $rtl_files]
add_files -norecurse -fileset constrs_1 $xdc_file
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

proc dump_drc_and_exit {stage} {
    set rpt "build_outputs/hdmi_colorbar_720p_only_drc_${stage}.rpt"
    catch {report_drc -file $rpt}
    puts "HDMI_COLORBAR_720P_ONLY_FAILED_STAGE=$stage"
    puts "HDMI_COLORBAR_720P_ONLY_DRC_REPORT=[file normalize $rpt]"
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
        puts "HDMI_COLORBAR_720P_ONLY_ERROR=$result"
        dump_drc_and_exit $stage
    }
}

run_or_drc synth {
    synth_design -top $top_module -part xc7k325tffg900-2
}
puts "HDMI_COLORBAR_720P_ONLY_SYNTH_OK"
report_utilization -file "build_outputs/util_${build_tag}_synth.rpt"

run_or_drc opt {
    opt_design
}
report_drc -file "build_outputs/hdmi_colorbar_720p_only_drc_opt.rpt"
puts "HDMI_COLORBAR_720P_ONLY_OPT_OK"

run_or_drc place {
    place_design
}
report_drc -file "build_outputs/hdmi_colorbar_720p_only_drc_placed.rpt"
puts "HDMI_COLORBAR_720P_ONLY_PLACE_OK"

run_or_drc route {
    route_design
}
report_drc -file "build_outputs/hdmi_colorbar_720p_only_drc_routed.rpt"
puts "HDMI_COLORBAR_720P_ONLY_ROUTE_OK"

set timing_rpt "build_outputs/timing_${build_tag}.rpt"
set util_rpt "build_outputs/util_${build_tag}_routed.rpt"
set drc_rpt "build_outputs/drc_${build_tag}_routed.rpt"
set clocks_rpt "build_outputs/clocks_${build_tag}_routed.rpt"
report_timing_summary -file $timing_rpt
report_utilization -file $util_rpt
report_drc -file $drc_rpt
report_clocks -file $clocks_rpt

run_or_drc bitstream {
    write_bitstream -force $bit_file
}

set final_bit "final_bits/${build_tag}.bit"
file copy -force $bit_file $final_bit
if {$input_clock_mode eq "125m"} {
    file copy -force $bit_file hdmi_colorbar_720p_only.bit
}

set worst_setup [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set worst_hold  [get_property SLACK [get_timing_paths -max_paths 1 -hold]]

set summary "build_outputs/summary_${build_tag}.txt"
set fp [open $summary w]
puts $fp "BUILD_TAG=$build_tag"
puts $fp "TOP=$top_module"
puts $fp "INPUT_CLOCK_MODE=$input_clock_mode"
puts $fp "CLOCK_NOTE=$clock_note"
puts $fp "MMCM=$mmcm_note"
puts $fp "VIDEO_MODE=1280x720@60"
puts $fp "HSYNC_POLARITY=positive"
puts $fp "VSYNC_POLARITY=positive"
puts $fp "PIXEL_CLK_MHZ=$pixel_clk_mhz"
puts $fp "TMDS_5X_CLK_MHZ=$tmds_5x_clk_mhz"
puts $fp "TMDS_MAPPING=hdmi_tx_data[0]=blue/control HDMI1_FD0, [1]=green HDMI1_FD1, [2]=red HDMI1_FD2"
puts $fp "WORST_SETUP_SLACK=$worst_setup"
puts $fp "WORST_HOLD_SLACK=$worst_hold"
puts $fp "BIT=[file normalize $bit_file]"
puts $fp "FINAL_BIT=[file normalize $final_bit]"
puts $fp "TIMING_REPORT=[file normalize $timing_rpt]"
puts $fp "UTIL_REPORT=[file normalize $util_rpt]"
puts $fp "DRC_REPORT=[file normalize $drc_rpt]"
puts $fp "CLOCKS_REPORT=[file normalize $clocks_rpt]"
close $fp

puts "HDMI_COLORBAR_720P_ONLY_BIT=[file normalize $bit_file]"
puts "HDMI_COLORBAR_720P_ONLY_FINAL_BIT=[file normalize $final_bit]"
puts "HDMI_COLORBAR_720P_ONLY_SUMMARY=[file normalize $summary]"
puts "HDMI_COLORBAR_720P_ONLY_DONE"
exit 0
