set timestamp [clock format [clock seconds] -format {%Y%m%d_%H%M%S}]
set part_name "xc7k325tffg900-2"
set xdc_file "digital_twin.srcs/constrs_1/new/hdmi_colorbar_720p_only_100m.xdc"

set rtl_files [list \
    digital_twin.srcs/sources_1/new/hdmi_colorbar_720p_tmds_variant_tops.sv \
    digital_twin.srcs/sources_1/new/hdmi_colorbar_720p_top_100m.sv \
    digital_twin.srcs/sources_1/new/hdmi_clock_gen_720p.sv \
    digital_twin.srcs/sources_1/new/hdmi_demo_720p.sv \
    digital_twin.srcs/sources_1/new/hdmi_out_7series.sv \
    digital_twin.srcs/sources_1/new/hdmi_test_pattern_720p.sv \
    digital_twin.srcs/sources_1/new/tmds_encoder.sv \
    digital_twin.srcs/sources_1/new/video_timing_1280x720.sv \
]

set variants [list \
    [list A lsb 1111100000 hdmi_colorbar_720p_100m_lsb_clkpat_1111100000] \
    [list B lsb 0000011111 hdmi_colorbar_720p_100m_lsb_clkpat_0000011111] \
    [list C msb 1111100000 hdmi_colorbar_720p_100m_msb_clkpat_1111100000] \
    [list D msb 0000011111 hdmi_colorbar_720p_100m_msb_clkpat_0000011111] \
]

file mkdir build_outputs
file mkdir final_bits

proc dump_drc_and_exit {stage label tag} {
    set rpt "build_outputs/drc_${tag}_${stage}.rpt"
    catch {report_drc -file $rpt}
    puts "HDMI_TMD_VARIANT_FAILED_LABEL=$label"
    puts "HDMI_TMD_VARIANT_FAILED_STAGE=$stage"
    puts "HDMI_TMD_VARIANT_DRC_REPORT=[file normalize $rpt]"
    if {[file exists $rpt]} {
        set fp [open $rpt r]
        puts [read $fp]
        close $fp
    }
    exit 1
}

proc run_or_drc {stage label tag cmd} {
    set code [catch {uplevel 1 $cmd} result]
    if {$code != 0} {
        puts "HDMI_TMD_VARIANT_ERROR=$result"
        dump_drc_and_exit $stage $label $tag
    }
}

set master_summary "build_outputs/summary_HDMI_COLORBAR_720p60_100m_tmds_variants_${timestamp}.txt"
set master_fp [open $master_summary w]
puts $master_fp "BUILD_SET=HDMI_COLORBAR_720p60_100m_tmds_variants_${timestamp}"
puts $master_fp "VIDEO_MODE=1280x720@60"
puts $master_fp "INPUT_CLOCK_MODE=100m"
puts $master_fp "MMCM=CLKIN=100MHz DIVCLK=5 MULT=37.125 CLKOUT0_DIV=10 CLKOUT1_DIV=2"
puts $master_fp "PIXEL_CLK_MHZ=74.25"
puts $master_fp "TMDS_5X_CLK_MHZ=371.25"
puts $master_fp "XDC=[file normalize $xdc_file]"
puts $master_fp ""

foreach variant $variants {
    lassign $variant label bit_order clk_pattern top_module

    set project_name "hdmi_720p60_100m_${label}_${bit_order}_clkpat_${clk_pattern}"
    set project_dir "build_outputs/${project_name}_project"
    set tag "HDMI_COLORBAR_720p60_100m_${label}_${bit_order}_clkpat_${clk_pattern}_${timestamp}"
    set bit_file "hdmi_colorbar_720p60_100m_${bit_order}_clkpat_${clk_pattern}.bit"
    set final_bit "final_bits/${tag}.bit"
    set timing_rpt "build_outputs/timing_${tag}.rpt"
    set util_rpt "build_outputs/util_${tag}_routed.rpt"
    set drc_rpt "build_outputs/drc_${tag}_routed.rpt"
    set clocks_rpt "build_outputs/clocks_${tag}_routed.rpt"
    set summary "build_outputs/summary_${tag}.txt"

    puts "HDMI_TMD_VARIANT_START=$label"
    puts "HDMI_TMD_VARIANT_TOP=$top_module"

    create_project $project_name $project_dir -part $part_name -force
    set_property target_language Verilog [current_project]
    set_property simulator_language Mixed [current_project]

    add_files -norecurse -fileset sources_1 $rtl_files
    set_property file_type SystemVerilog [get_files $rtl_files]
    add_files -norecurse -fileset constrs_1 $xdc_file
    set_property top $top_module [current_fileset]
    update_compile_order -fileset sources_1

    run_or_drc synth $label $tag {
        synth_design -top $top_module -part $part_name
    }
    report_utilization -file "build_outputs/util_${tag}_synth.rpt"

    run_or_drc opt $label $tag {
        opt_design
    }
    report_drc -file "build_outputs/drc_${tag}_opt.rpt"

    run_or_drc place $label $tag {
        place_design
    }
    report_drc -file "build_outputs/drc_${tag}_placed.rpt"

    run_or_drc route $label $tag {
        route_design
    }
    report_drc -file $drc_rpt
    report_timing_summary -file $timing_rpt
    report_utilization -file $util_rpt
    report_clocks -file $clocks_rpt

    run_or_drc bitstream $label $tag {
        write_bitstream -force $bit_file
    }
    file copy -force $bit_file $final_bit

    set worst_setup [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
    set worst_hold  [get_property SLACK [get_timing_paths -max_paths 1 -hold]]

    set fp [open $summary w]
    puts $fp "VARIANT=$label"
    puts $fp "TOP=$top_module"
    puts $fp "INPUT_CLOCK_MODE=100m"
    puts $fp "VIDEO_MODE=1280x720@60"
    puts $fp "TMDS_DATA_ORDER=$bit_order"
    puts $fp "HDMI_CLK_PATTERN=10'b$clk_pattern"
    puts $fp "MMCM=CLKIN=100MHz DIVCLK=5 MULT=37.125 CLKOUT0_DIV=10 CLKOUT1_DIV=2"
    puts $fp "PIXEL_CLK_MHZ=74.25"
    puts $fp "TMDS_5X_CLK_MHZ=371.25"
    puts $fp "WORST_SETUP_SLACK=$worst_setup"
    puts $fp "WORST_HOLD_SLACK=$worst_hold"
    puts $fp "BIT=[file normalize $bit_file]"
    puts $fp "FINAL_BIT=[file normalize $final_bit]"
    puts $fp "TIMING_REPORT=[file normalize $timing_rpt]"
    puts $fp "UTIL_REPORT=[file normalize $util_rpt]"
    puts $fp "DRC_REPORT=[file normalize $drc_rpt]"
    puts $fp "CLOCKS_REPORT=[file normalize $clocks_rpt]"
    close $fp

    puts $master_fp "VARIANT=$label"
    puts $master_fp "TOP=$top_module"
    puts $master_fp "TMDS_DATA_ORDER=$bit_order"
    puts $master_fp "HDMI_CLK_PATTERN=10'b$clk_pattern"
    puts $master_fp "WORST_SETUP_SLACK=$worst_setup"
    puts $master_fp "WORST_HOLD_SLACK=$worst_hold"
    puts $master_fp "BIT=[file normalize $bit_file]"
    puts $master_fp "FINAL_BIT=[file normalize $final_bit]"
    puts $master_fp "SUMMARY=[file normalize $summary]"
    puts $master_fp ""
    flush $master_fp

    puts "HDMI_TMD_VARIANT_DONE=$label"
    puts "HDMI_TMD_VARIANT_BIT=[file normalize $bit_file]"
    puts "HDMI_TMD_VARIANT_FINAL_BIT=[file normalize $final_bit]"
    puts "HDMI_TMD_VARIANT_SUMMARY=[file normalize $summary]"

    close_project
}

close $master_fp
puts "HDMI_TMD_VARIANTS_MASTER_SUMMARY=[file normalize $master_summary]"
puts "HDMI_TMD_VARIANTS_DONE"
exit 0
