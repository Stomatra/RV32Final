open_checkpoint {e:/Projects/1Aprojects/RV32Final/timing_backups/place_explore_compare_20260628_190347/top_Explore.dcp}
set delta [expr {5.000 - (1000.0 / 202.25)}]
puts "PERIOD_DELTA=$delta"
set_clock_uncertainty $delta [get_clocks clk_out2_pll]
report_timing_summary -max_paths 10 -file {e:/Projects/1Aprojects/RV32Final/timing_backups/place_explore_compare_20260628_190347/timing_whatif_uncertainty_202p25.rpt}
close_design
exit
