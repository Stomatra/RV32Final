open_checkpoint {e:/Projects/1Aprojects/RV32Final/timing_backups/place_explore_compare_20260628_190347/top_Explore.dcp}
puts "CLOCKS_BEFORE"
report_clocks
set target_period [expr {1000.0 / 202.25}]
puts "TARGET_PERIOD=$target_period"
set clk [get_clocks clk_out2_pll]
puts "CLK_COUNT=[llength $clk]"
catch {set_property PERIOD $target_period $clk} period_err
puts "PERIOD_ERR=$period_err"
report_timing_summary -max_paths 10 -file {e:/Projects/1Aprojects/RV32Final/timing_backups/place_explore_compare_20260628_190347/timing_whatif_202p25.rpt}
close_design
exit
