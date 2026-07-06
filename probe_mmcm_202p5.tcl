open_project digital_twin.xpr
set pll_ip [get_ips pll]
puts "CURRENT_PRIMITIVE=[get_property CONFIG.PRIMITIVE $pll_ip]"
puts "CURRENT_CLKOUT1=[get_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $pll_ip]"
puts "CURRENT_CLKOUT2=[get_property CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $pll_ip]"
catch {set_property -dict [list CONFIG.PRIMITIVE {MMCM} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 50.0 CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 202.5] $pll_ip} set_err
puts "SET_ERR=$set_err"
puts "NEW_PRIMITIVE=[get_property CONFIG.PRIMITIVE $pll_ip]"
puts "NEW_CLKOUT1=[get_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $pll_ip]"
puts "NEW_CLKOUT2=[get_property CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $pll_ip]"
set cfg_lines [report_property -return_string $pll_ip]
puts $cfg_lines
close_project
exit
