open_project digital_twin.xpr
set pll_ip [get_ips pll]
set pll_xci [get_files {e:/Projects/1Aprojects/RV32Final/digital_twin.srcs/sources_1/ip/pll_1/pll.xci}]
upgrade_ip $pll_ip
set_property -dict [list CONFIG.PRIMITIVE {PLL} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 50.0 CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 200.0] $pll_ip
reset_target all $pll_xci
generate_target all $pll_xci
export_ip_user_files -of_objects $pll_xci -no_script -sync -force -quiet
if {[llength [get_runs pll_synth_1]] == 0} { create_ip_run $pll_xci }
reset_run pll_synth_1
launch_runs pll_synth_1 -jobs 2
wait_on_run pll_synth_1
puts "PLL_XCI=$pll_xci"
puts "PLL_DCP_EXISTS=[file exists {e:/Projects/1Aprojects/RV32Final/digital_twin.gen/sources_1/ip/pll/pll.dcp}]"
close_project
exit
