set_property PACKAGE_PIN AD12 [get_ports i_sys_clk_p]
set_property PACKAGE_PIN AD11 [get_ports i_sys_clk_n]
set_property IOSTANDARD DIFF_HSTL_II_18 [get_ports i_sys_clk_p]
set_property IOSTANDARD DIFF_HSTL_II_18 [get_ports i_sys_clk_n]
create_clock -period 5.000 -name sys_clk_200m [get_ports i_sys_clk_p]

set_property PACKAGE_PIN D17 [get_ports o_uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports o_uart_tx]

set_property PACKAGE_PIN D29 [get_ports hdmi_hpd]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_hpd]

set_property PACKAGE_PIN D27 [get_ports hdmi_tx_clk_p]
set_property PACKAGE_PIN C27 [get_ports hdmi_tx_clk_n]
set_property PACKAGE_PIN B30 [get_ports {hdmi_tx_data_p[2]}]
set_property PACKAGE_PIN A30 [get_ports {hdmi_tx_data_n[2]}]
set_property PACKAGE_PIN G29 [get_ports {hdmi_tx_data_p[1]}]
set_property PACKAGE_PIN F30 [get_ports {hdmi_tx_data_n[1]}]
set_property PACKAGE_PIN H30 [get_ports {hdmi_tx_data_p[0]}]
set_property PACKAGE_PIN G30 [get_ports {hdmi_tx_data_n[0]}]

set_property IOSTANDARD TMDS_33 [get_ports hdmi_tx_clk_p]
set_property IOSTANDARD TMDS_33 [get_ports hdmi_tx_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_data_p[*]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_data_n[*]}]

# Debug-only CDC paths: pixel/frame counters are Gray-coded before being
# sampled by the UART/sys_clk domain synchronizers. HPD and MMCM locked are
# also sampled through two-flop synchronizers.
set_false_path -from [get_clocks -quiet pixel_clk_unbuf] -to [get_clocks -quiet sys_clk_200m]
set_false_path -from [get_ports -quiet hdmi_hpd] -to [get_pins -quiet hpd_sync_reg[*]/D]
