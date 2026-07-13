open_project digital_twin.xpr
set_property top top [current_fileset]
set_property verilog_define {ENABLE_HDMI_DEMO} [get_filesets sources_1]
update_compile_order -fileset sources_1

set build_tag "HDMI_COLORBAR_640x480_60_[clock format [clock seconds] -format {%Y%m%d_%H%M%S}]"
file mkdir build_outputs
file mkdir final_bits

if {[get_property PROGRESS [get_runs synth_1]] != "0%"} {
    reset_run synth_1
}
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "HDMI_COLORBAR_SYNTH_STATUS=$synth_status"
if {![string match "*Complete*" $synth_status]} {
    puts "HDMI_COLORBAR_SYNTH_FAILED"
    exit 1
}

if {[get_property PROGRESS [get_runs impl_1]] != "0%"} {
    reset_run impl_1
}
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "HDMI_COLORBAR_IMPL_STATUS=$impl_status"
if {![string match "*Complete*" $impl_status]} {
    puts "HDMI_COLORBAR_IMPL_FAILED"
    exit 1
}

open_run impl_1
set timing_rpt "build_outputs/timing_${build_tag}.rpt"
set util_rpt "build_outputs/util_${build_tag}.rpt"
report_timing_summary -file $timing_rpt
report_utilization -file $util_rpt

set worst_setup [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set worst_hold  [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
puts "HDMI_COLORBAR_WNS=$worst_setup"
puts "HDMI_COLORBAR_WHS=$worst_hold"

set impl_bit "digital_twin.runs/impl_1/top.bit"
set final_bit "final_bits/${build_tag}.bit"
set stable_bit "hdmi_colorbar.bit"
file copy -force $impl_bit $final_bit
file copy -force $impl_bit $stable_bit

set summary "build_outputs/summary_${build_tag}.txt"
set fp [open $summary w]
puts $fp "BUILD_TAG=$build_tag"
puts $fp "DEFINE=ENABLE_HDMI_DEMO"
puts $fp "VIDEO_MODE=640x480@60"
puts $fp "PIXEL_CLK_MHZ=25.2"
puts $fp "TMDS_5X_CLK_MHZ=126.0"
puts $fp "SYNTH_STATUS=$synth_status"
puts $fp "IMPL_STATUS=$impl_status"
puts $fp "WORST_SETUP_SLACK=$worst_setup"
puts $fp "WORST_HOLD_SLACK=$worst_hold"
puts $fp "FINAL_BIT=[file normalize $final_bit]"
puts $fp "STABLE_BIT=[file normalize $stable_bit]"
puts $fp "TIMING_REPORT=[file normalize $timing_rpt]"
puts $fp "UTIL_REPORT=[file normalize $util_rpt]"
close $fp

puts "HDMI_COLORBAR_BUILD_TAG=$build_tag"
puts "HDMI_COLORBAR_FINAL_BIT=[file normalize $final_bit]"
puts "HDMI_COLORBAR_STABLE_BIT=[file normalize $stable_bit]"
puts "HDMI_COLORBAR_SUMMARY=[file normalize $summary]"
exit 0
