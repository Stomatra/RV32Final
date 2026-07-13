set_property PACKAGE_PIN AD12 [get_ports i_sys_clk_p]
set_property PACKAGE_PIN AD11 [get_ports i_sys_clk_n]
set_property IOSTANDARD DIFF_HSTL_II_18 [get_ports i_sys_clk_p]
set_property IOSTANDARD DIFF_HSTL_II_18 [get_ports i_sys_clk_n]
create_clock -period 5.000 -name sys_clk_200m [get_ports i_sys_clk_p]

set_property PACKAGE_PIN D18 [get_ports i_uart_rx]
set_property PACKAGE_PIN D17 [get_ports o_uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports i_uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports o_uart_tx]

set_property PACKAGE_PIN D29 [get_ports hdmi_hpd]
set_property IOSTANDARD LVCMOS33 [get_ports hdmi_hpd]

# Keep the CPU status clock generator close to the sysclk CCIO region.
set_property LOC MMCME2_ADV_X1Y1 [get_cells cpu_clock_gen_inst/mmcm_inst]

# HDMI TMDS lanes are in Bank16 / clock region X0Y4. The reference serializer
# uses the same clocking placement that was verified on the standalone 720p bit.
set_property LOC MMCME2_ADV_X0Y4 [get_cells hdmi_clock_gen_inst/mmcm_inst]
set_property CLOCK_DEDICATED_ROUTE ANY_CMT_COLUMN [get_nets sys_clk]

# CPU LED/SEG values are sampled by two-flop synchronizers for the HDMI status
# overlay. Treat that status-display crossing as asynchronous.
set_false_path -from [get_clocks cpu_clk_unbuf] -to [get_clocks pixel_clk]

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
