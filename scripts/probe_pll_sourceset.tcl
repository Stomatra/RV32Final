open_project digital_twin.xpr
set fs [get_filesets sources_1]
puts "FS_PLL_XCI=[get_files -quiet -of_objects $fs *pll*.xci]"
puts "ALL_IPS=[get_ips]"
puts "IP_PLL_FILES=[get_files -quiet -of_objects [get_ips pll]]"
close_project
