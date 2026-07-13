set_property PACKAGE_PIN AD12 [get_ports i_sys_clk_p]
set_property PACKAGE_PIN AD11 [get_ports i_sys_clk_n]
set_property IOSTANDARD DIFF_HSTL_II_18 [get_ports i_sys_clk_p]
set_property IOSTANDARD DIFF_HSTL_II_18 [get_ports i_sys_clk_n]
create_clock -period 5.000 -name sys_clk_200m [get_ports i_sys_clk_p]

# HDMI TMDS lanes are in Bank16 / clock region X0Y4. Keep the reference
# serializer MMCM in the same region so its 5x clock can legally drive BUFIO.
set_property LOC MMCME2_ADV_X0Y4 [get_cells hdmi_clock_gen_inst/mmcm_inst]

# The board sysclk pins AD12/AD11 are in clock region X1Y1, while the HDMI
# serializer must use the Bank16 CMT in X0Y4 for legal BUFIO/BUFR routing.
# Keep this override local to the standalone HDMI reference build.
set_property CLOCK_DEDICATED_ROUTE ANY_CMT_COLUMN [get_nets sys_clk]

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
