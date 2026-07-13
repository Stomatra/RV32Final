set project_dir "build_outputs/hdmi_colorbar_only_project"
set project_name "hdmi_colorbar_only"
set build_tag "HDMI_COLORBAR_ONLY_640x480_60_[clock format [clock seconds] -format {%Y%m%d_%H%M%S}]"

file mkdir build_outputs
file mkdir final_bits

create_project $project_name $project_dir -part xc7k325tffg900-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [list \
    digital_twin.srcs/sources_1/new/hdmi_colorbar_top.sv \
    digital_twin.srcs/sources_1/new/hdmi_clock_gen.sv \
    digital_twin.srcs/sources_1/new/hdmi_demo.sv \
    digital_twin.srcs/sources_1/new/hdmi_out_7series.sv \
    digital_twin.srcs/sources_1/new/hdmi_test_pattern.sv \
    digital_twin.srcs/sources_1/new/tmds_encoder.sv \
    digital_twin.srcs/sources_1/new/video_timing_640x480.sv \
]

add_files -norecurse -fileset sources_1 $rtl_files
set_property file_type SystemVerilog [get_files $rtl_files]
add_files -norecurse -fileset constrs_1 digital_twin.srcs/constrs_1/new/hdmi_colorbar_only.xdc
set_property top hdmi_colorbar_top [current_fileset]
update_compile_order -fileset sources_1

proc dump_drc_and_exit {stage} {
    set rpt "build_outputs/hdmi_colorbar_only_drc_${stage}.rpt"
    catch {report_drc -file $rpt}
    puts "HDMI_COLORBAR_ONLY_FAILED_STAGE=$stage"
    puts "HDMI_COLORBAR_ONLY_DRC_REPORT=[file normalize $rpt]"
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
        puts "HDMI_COLORBAR_ONLY_ERROR=$result"
        dump_drc_and_exit $stage
    }
}

run_or_drc synth {
    synth_design -top hdmi_colorbar_top -part xc7k325tffg900-2
}
puts "HDMI_COLORBAR_ONLY_SYNTH_OK"
report_utilization -file "build_outputs/util_${build_tag}_synth.rpt"

run_or_drc opt {
    opt_design
}
report_drc -file "build_outputs/hdmi_colorbar_only_drc_opt.rpt"
puts "HDMI_COLORBAR_ONLY_OPT_OK"

run_or_drc place {
    place_design
}
report_drc -file "build_outputs/hdmi_colorbar_only_drc_placed.rpt"
puts "HDMI_COLORBAR_ONLY_PLACE_OK"

run_or_drc route {
    route_design
}
report_drc -file "build_outputs/hdmi_colorbar_only_drc_routed.rpt"
puts "HDMI_COLORBAR_ONLY_ROUTE_OK"

set timing_rpt "build_outputs/timing_${build_tag}.rpt"
set util_rpt "build_outputs/util_${build_tag}_routed.rpt"
report_timing_summary -file $timing_rpt
report_utilization -file $util_rpt

run_or_drc bitstream {
    write_bitstream -force hdmi_colorbar_only.bit
}

set final_bit "final_bits/${build_tag}.bit"
file copy -force hdmi_colorbar_only.bit $final_bit

set worst_setup [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set worst_hold  [get_property SLACK [get_timing_paths -max_paths 1 -hold]]

set summary "build_outputs/summary_${build_tag}.txt"
set fp [open $summary w]
puts $fp "BUILD_TAG=$build_tag"
puts $fp "TOP=hdmi_colorbar_top"
puts $fp "VIDEO_MODE=640x480@60"
puts $fp "PIXEL_CLK_MHZ=25.2"
puts $fp "TMDS_5X_CLK_MHZ=126.0"
puts $fp "WORST_SETUP_SLACK=$worst_setup"
puts $fp "WORST_HOLD_SLACK=$worst_hold"
puts $fp "BIT=[file normalize hdmi_colorbar_only.bit]"
puts $fp "FINAL_BIT=[file normalize $final_bit]"
puts $fp "TIMING_REPORT=[file normalize $timing_rpt]"
puts $fp "UTIL_REPORT=[file normalize $util_rpt]"
close $fp

puts "HDMI_COLORBAR_ONLY_BIT=[file normalize hdmi_colorbar_only.bit]"
puts "HDMI_COLORBAR_ONLY_FINAL_BIT=[file normalize $final_bit]"
puts "HDMI_COLORBAR_ONLY_SUMMARY=[file normalize $summary]"
puts "HDMI_COLORBAR_ONLY_DONE"
exit 0
