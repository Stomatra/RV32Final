set project_root [file normalize {E:/Projects/1Aprojects/RV32Final}]
set xpr          [file normalize {E:/Projects/1Aprojects/RV32Final/digital_twin.xpr}]
set out_dir      [file normalize {E:/Projects/1Aprojects/RV32Final/build_outputs}]
set out_bit      [file normalize {E:/Projects/1Aprojects/RV32Final/build_outputs/top_withoutmext_irom_v2_150m_normal_rebuild.bit}]
set timing_rpt   [file normalize {E:/Projects/1Aprojects/RV32Final/build_outputs/timing_withoutmext_irom_v2_150m_normal_rebuild.rpt}]
set jobs         8

puts "Opening project: $xpr"
open_project $xpr

# 娓呴櫎鎵€鏈夎皟璇曞畯锛岄伩鍏?DEBUG_HW_MILESTONE / LED_WALK_TEST 娈嬬暀
set fs [get_filesets sources_1]
set_property verilog_define {} $fs
puts "sources_1 verilog_define = [get_property verilog_define $fs]"

# 鏇存柊 compile order
update_compile_order -fileset sources_1

# 閲嶆柊鐢熸垚 IP output products
puts "Regenerating IP output products..."
foreach ip [get_ips] {
    puts "generate_target all $ip"
    generate_target all $ip
}

# 閲嶈窇鎵€鏈?IP synth run
set ip_runs [get_runs *_synth_1]
if {[llength $ip_runs] > 0} {
    foreach r $ip_runs {
        catch { reset_run $r }
    }
    launch_runs $ip_runs -jobs $jobs
    foreach r $ip_runs {
        wait_on_run $r
    }
}

# 閲嶆柊缁煎悎
puts "Reset synth_1..."
catch { reset_run synth_1 }
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1

# 璁剧疆瀹炵幇绛栫暐
puts "Set impl_1 strategy Performance_Explore..."
set_property strategy Performance_Explore [get_runs impl_1]

# 鎵撳紑 phys_opt锛岃繘涓€姝ョǔ浣?timing
catch {
    set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
    set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
}

# 閲嶆柊瀹炵幇骞跺啓 bit
puts "Reset impl_1..."
catch { reset_run impl_1 }
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1

open_run impl_1

# 瀵煎嚭 timing
report_timing_summary -file $timing_rpt -delay_type max -report_unconstrained -check_timing_verbose

# 澶嶅埗 bit
set impl_bit [file normalize [file join $project_root "digital_twin.runs" "impl_1" "top.bit"]]
if {![file exists $impl_bit]} {
    error "Cannot find generated bit: $impl_bit"
}

file copy -force $impl_bit $out_bit

puts "BIT_OUT=$out_bit"
puts "TIMING_RPT=$timing_rpt"
puts "Build finished."
close_project